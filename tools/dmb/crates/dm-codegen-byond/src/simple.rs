//! Direct lowering of a deliberately small DM procedure subset. Unsupported
//! constructs are errors; the emitter must never silently change semantics.
use crate::{
    Instruction, Item as CodeItem, SymbolicProc, ValueWord, VariableWord, Word,
    BUILTIN_GLOBAL_VARS_SYMBOL,
};
use byond_dmb::bytecode::opcode;
use dm_syntax::{
    parse_body_items, parse_expression, Expr, ExprKind, ForControl, ForInitializer, Item,
    Statement, StatementKind, SwitchAlternative,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub enum LowerErrorKind {
    SourceError,
    #[default]
    UnsupportedModel,
    Internal,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerSpan {
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerError {
    pub statement: String,
    pub reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub span: Option<LowerSpan>,
    #[serde(default)]
    pub kind: LowerErrorKind,
}

impl LowerError {
    fn at(mut self, span: Option<LowerSpan>) -> Self {
        if self.span.is_none() {
            self.span = span;
        }
        self
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct SimpleProc {
    pub code: SymbolicProc,
    /// Every literal/field string referenced by `code`, in first-use order.
    pub strings: Vec<String>,
    /// Native format templates use non-UTF-8 control bytes; their symbolic keys
    /// are present in `strings` and resolve to these exact payloads.
    pub format_templates: HashMap<String, Vec<u8>>,
    pub class_paths: Vec<String>,
    #[serde(default)]
    pub instance_paths: Vec<String>,
    pub resources: Vec<String>,
    pub local_count: u32,
    /// Local declaration names in native local-slot order. The DMB writer
    /// resolves these names to VarIDs and writes that list as proc metadata.
    pub local_names: Vec<String>,
    /// Formal names and restriction flags in native Arg-slot order.
    pub argument_names: Vec<String>,
    pub argument_type_flags: Vec<u32>,
    pub argument_value_sources: Vec<u32>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ArgumentMetadata {
    pub name: String,
    pub type_flags: u32,
    pub value_source: u32,
    pub reserved: u32,
}

impl SimpleProc {
    pub fn string_bytes<'a>(&'a self, key: &'a str) -> &'a [u8] {
        self.format_templates
            .get(key)
            .map(Vec::as_slice)
            .unwrap_or_else(|| key.as_bytes())
    }
    pub fn argument_metadata(&self) -> Vec<ArgumentMetadata> {
        self.argument_names
            .iter()
            .enumerate()
            .map(|(index, name)| ArgumentMetadata {
                name: name.clone(),
                type_flags: self.argument_type_flags.get(index).copied().unwrap_or(0),
                value_source: self
                    .argument_value_sources
                    .get(index)
                    .copied()
                    .unwrap_or(0x7d01),
                reserved: 0,
            })
            .collect()
    }
}

/// Names resolved by the declaration index before bytecode lowering.
#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerBindings {
    #[serde(skip)]
    pub procedure_identity: Option<dm_ir::ProcedureIdentity>,
    /// Canonical path of the procedure being lowered, for compiler context values.
    pub current_proc_path: Option<String>,
    /// Canonical owner path, absent for global procedures.
    pub current_type_path: Option<String>,
    pub parameters: Vec<String>,
    pub parameter_type_flags: Vec<u32>,
    pub parameter_value_sources: Vec<u32>,
    pub parameter_defaults: Vec<Option<String>>,
    /// Declared parameter paths for type-inferred built-ins such as `istype(x)`.
    pub parameter_types: HashMap<String, String>,
    #[serde(default, skip_serializing_if = "BTreeSet::is_empty")]
    pub readonly_parameters: BTreeSet<u32>,
    pub fields: BTreeSet<String>,
    pub globals: BTreeSet<String>,
    /// Declared type paths used to resolve `new(args)` without an explicit path.
    pub field_types: HashMap<String, String>,
    pub global_types: HashMap<String, String>,
    /// Global procedure names resolvable to ProcIDs at link time.
    pub global_procs: BTreeSet<String>,
    /// Immutable project-wide names shared between procedure lowering jobs.
    #[serde(skip)]
    pub shared: Option<Arc<SharedLowerBindings>>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct SharedLowerBindings {
    /// Stable modified-type aliases mapped to their original runtime type.
    #[serde(default)]
    pub modified_instances: HashMap<String, String>,
    /// Per-member semantic digests prepared once for portable lowering cache keys.
    #[serde(skip)]
    pub member_type_fingerprints: HashMap<String, String>,
    pub member_types: HashMap<String, HashMap<String, String>>,
    /// Class global/static members resolved directly to their shared variable slot.
    #[serde(default)]
    pub member_globals: HashMap<String, HashMap<String, String>>,
    /// Complete declared field inventory, including untyped instance fields.
    #[serde(default)]
    pub known_member_fields: HashMap<String, BTreeSet<String>>,
    /// Directly declared procedure paths by owner and source name.
    pub member_procs: HashMap<String, HashMap<String, String>>,
    /// Complete declaration inventory, separate from static call selection.
    #[serde(default)]
    pub known_member_procs: HashMap<String, BTreeSet<String>>,
    pub parent_types: HashMap<String, String>,
    pub fields: BTreeSet<String>,
    pub globals: BTreeSet<String>,
    pub field_types: HashMap<String, String>,
    pub global_types: HashMap<String, String>,
    pub global_procs: BTreeSet<String>,
    /// Native predefined numeric names such as UNIX, when no lexical name shadows them.
    pub numeric_constants: HashMap<String, u32>,
    /// Native predefined string names such as UNIX, when no lexical name shadows them.
    pub string_constants: HashMap<String, String>,
    /// Canonical digest computed once by declaration indexing, then used by the lowering cache.
    #[serde(skip)]
    pub fingerprint: String,
}

impl LowerBindings {
    fn has_field(&self, name: &str) -> bool {
        self.fields.contains(name)
            || self
                .shared
                .as_ref()
                .is_some_and(|shared| shared.fields.contains(name))
    }

    fn has_global(&self, name: &str) -> bool {
        self.globals.contains(name)
            || self
                .shared
                .as_ref()
                .is_some_and(|shared| shared.globals.contains(name))
    }

    fn has_global_proc(&self, name: &str) -> bool {
        self.global_procs.contains(name)
            || self
                .shared
                .as_ref()
                .is_some_and(|shared| shared.global_procs.contains(name))
    }

    fn field_type(&self, name: &str) -> Option<&str> {
        self.field_types
            .get(name)
            .or_else(|| self.shared.as_ref()?.field_types.get(name))
            .map(String::as_str)
    }

    fn global_type(&self, name: &str) -> Option<&str> {
        self.global_types
            .get(name)
            .or_else(|| self.shared.as_ref()?.global_types.get(name))
            .map(String::as_str)
    }

    fn member_type(&self, owner: &str, name: &str) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        let mut path = shared
            .modified_instances
            .get(owner)
            .map(String::as_str)
            .unwrap_or(owner);
        for _ in 0..64 {
            if let Some(member) = shared
                .member_types
                .get(path)
                .and_then(|members| members.get(name))
            {
                return Some(member);
            }
            path = shared.parent_types.get(path)?;
        }
        None
    }

    fn member_global(&self, owner: &str, name: &str) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        let mut path = shared
            .modified_instances
            .get(owner)
            .map(String::as_str)
            .unwrap_or(owner);
        for _ in 0..64 {
            if let Some(symbol) = shared
                .member_globals
                .get(path)
                .and_then(|members| members.get(name))
            {
                return Some(symbol);
            }
            path = shared.parent_types.get(path)?;
        }
        None
    }

    fn unique_member_global(&self, name: &str) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        if shared.known_member_fields.iter().any(|(owner, members)| {
            members.contains(name) && self.member_global(owner, name).is_none()
        }) {
            return None;
        }
        let mut found: Option<&str> = None;
        for members in shared.member_globals.values() {
            if let Some(symbol) = members.get(name) {
                if found.is_some_and(|previous| previous != symbol) {
                    return None;
                }
                found = Some(symbol);
            }
        }
        found
    }

    fn member_proc(&self, owner: &str, name: &str) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        let mut path = shared
            .modified_instances
            .get(owner)
            .map(String::as_str)
            .unwrap_or(owner);
        for _ in 0..64 {
            if let Some(proc_path) = shared
                .member_procs
                .get(path)
                .and_then(|members| members.get(name))
            {
                return Some(proc_path);
            }
            path = shared.parent_types.get(path)?;
        }
        None
    }

    fn has_declared_member_proc(&self, owner: &str, name: &str) -> bool {
        let Some(shared) = self.shared.as_ref() else {
            return false;
        };
        let mut path = shared
            .modified_instances
            .get(owner)
            .map(String::as_str)
            .unwrap_or(owner);
        for _ in 0..64 {
            if shared
                .known_member_procs
                .get(path)
                .is_some_and(|names| names.contains(name))
            {
                return true;
            }
            let Some(parent) = shared.parent_types.get(path) else {
                return false;
            };
            path = parent;
        }
        false
    }
}

pub fn compile_simple_proc(body: &[Item]) -> Result<SimpleProc, Vec<LowerError>> {
    compile_simple_proc_with_params(body, &[])
}

pub fn compile_simple_proc_with_params(
    body: &[Item],
    params: &[String],
) -> Result<SimpleProc, Vec<LowerError>> {
    compile_simple_proc_with_bindings(
        body,
        &LowerBindings {
            parameters: params.to_vec(),
            ..LowerBindings::default()
        },
    )
}

pub fn compile_simple_proc_with_bindings(
    body: &[Item],
    bindings: &LowerBindings,
) -> Result<SimpleProc, Vec<LowerError>> {
    compile_with_lookup(body, None, bindings, None, None)
}

pub fn compile_simple_proc_with_resolver<R: dm_ir::Resolver>(
    body: &[Item],
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    compile_simple_proc_with_resolver_and_debug(body, inputs, symbols, resolver, None)
}

/// Source origins are borrowed per occurrence; reusable code retains only ordinals.
pub trait DebugSourceProvider {
    fn entry_ordinal(&self) -> Result<u32, String>;
    fn ordinal(&self, expanded_offset: usize) -> Result<u32, String>;
}
pub fn compile_simple_proc_with_resolver_and_debug<R: dm_ir::Resolver>(
    body: &[Item],
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    compile_resolver_body(body, None, inputs, symbols, resolver, debug)
}

/// Lower already parsed statements through the same opcode/operand emitter.
/// No synthetic procedure text or alternate initializer opcode implementation.
pub fn compile_typed_statements_with_resolver<R: dm_ir::Resolver>(
    statements: &[Statement],
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    compile_resolver_body(
        &[],
        Some(TypedInput::Statements(statements)),
        inputs,
        symbols,
        resolver,
        debug,
    )
}

/// One VM invocation, with one resolver and code/label/debug accumulator.
pub fn compile_typed_scopes_with_resolver<R: dm_ir::Resolver>(
    scopes: &[crate::typed_scopes::TypedScope<'_>],
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    let prepared = crate::typed_scopes::prepare(scopes)?;
    let bindings = LowerBindings::default();
    let lookup = crate::lower_resolver::ProjectResolver {
        modified_instances: std::cell::RefCell::new(Default::default()),
        procedure_values: std::cell::RefCell::new(Default::default()),
        procedure_statics: std::cell::RefCell::new(Default::default()),
        resolver,
        symbols,
        slots: std::cell::RefCell::new(Default::default()),
        resources: std::cell::RefCell::new(Default::default()),
        instances: std::cell::RefCell::new(Default::default()),
        runtime_types: std::cell::RefCell::new(Default::default()),
        resource_search_context: prepared.resource_search_context,
    };
    let procedure = compile_with_lookup(
        &[],
        Some(TypedInput::Scopes(&prepared.scopes)),
        &bindings,
        Some(&lookup),
        debug,
    )?;
    Ok(crate::lower_resolver::ResolverProc {
        modified_instances: lookup.modified_instances.into_inner(),
        procedure_values: lookup.procedure_values.into_inner(),
        procedure_statics: lookup.procedure_statics.into_inner(),
        procedure,
        slots: lookup.slots.into_inner(),
        resources: lookup.resources.into_inner(),
        instances: lookup.instances.into_inner(),
    })
}

fn compile_resolver_body<R: dm_ir::Resolver>(
    body: &[Item],
    typed: Option<TypedInput<'_>>,
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    let bindings = inputs.lexical_bindings();
    let lookup = crate::lower_resolver::ProjectResolver {
        modified_instances: std::cell::RefCell::new(Default::default()),
        procedure_values: std::cell::RefCell::new(Default::default()),
        procedure_statics: std::cell::RefCell::new(Default::default()),
        resolver,
        symbols,
        slots: std::cell::RefCell::new(Default::default()),
        resources: std::cell::RefCell::new(Default::default()),
        instances: std::cell::RefCell::new(Default::default()),
        runtime_types: std::cell::RefCell::new(Default::default()),
        resource_search_context: inputs.resource_search_context,
    };
    let procedure = compile_with_lookup(body, typed, &bindings, Some(&lookup), debug)?;
    Ok(crate::lower_resolver::ResolverProc {
        modified_instances: lookup.modified_instances.into_inner(),
        procedure_values: lookup.procedure_values.into_inner(),
        procedure_statics: lookup.procedure_statics.into_inner(),
        procedure,
        slots: lookup.slots.into_inner(),
        resources: lookup.resources.into_inner(),
        instances: lookup.instances.into_inner(),
    })
}

#[derive(Clone, Copy)]
enum TypedInput<'a> {
    Statements(&'a [Statement]),
    Scopes(&'a [crate::typed_scopes::PreparedScope<'a>]),
    Modified(&'a [(String, Expr)]),
}
/// This boundary is crate-private: initializer::lower_modified_assignments
/// admits target/RHS semantics before selecting the certified Src setter.
pub(crate) fn compile_modified_fields_with_resolver<R: dm_ir::Resolver>(
    fields: &[(String, Expr)],
    inputs: &crate::lower_resolver::ProcedureInputs,
    symbols: &dm_ir::SymbolTable,
    resolver: &R,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<crate::lower_resolver::ResolverProc, Vec<LowerError>> {
    compile_resolver_body(
        &[],
        Some(TypedInput::Modified(fields)),
        inputs,
        symbols,
        resolver,
        debug,
    )
}
fn compile_with_lookup(
    body: &[Item],
    typed: Option<TypedInput<'_>>,
    bindings: &LowerBindings,
    lookup: Option<&crate::lower_resolver::ProjectResolver<'_>>,
    debug: Option<&dyn DebugSourceProvider>,
) -> Result<SimpleProc, Vec<LowerError>> {
    let mut compiler = Compiler {
        result: SimpleProc::default(),
        bindings,
        lookup,
        debug,
        debug_current: None,
        debug_last: None,
        statement_span: None,
        discarded_call_root: None,
        resolver_failure: std::cell::RefCell::new(None),
        locals: Vec::new(),
        local_slots: HashMap::new(),
        local_types: HashMap::new(),
        seen_strings: BTreeSet::new(),
        seen_classes: BTreeSet::new(),
        seen_resources: BTreeSet::new(),
        next_label: 0,
        label_try_depths: HashMap::new(),
        user_labels: HashMap::new(),
        user_label_iterator_depths: HashMap::new(),
        label_breaks: HashMap::new(),
        label_loop_depths: HashMap::new(),
        label_iterator_depths: HashMap::new(),
        try_depth: 0,
        loops: Vec::new(),
        breaks: Vec::new(),
        iterator_depth: 0,
    };
    if let Some(provider) = debug {
        compiler.debug_current = Some(
            provider
                .entry_ordinal()
                .map_err(|reason| vec![error("procedure header", &reason)])?,
        );
    }
    compiler.parameter_defaults().map_err(|error| vec![error])?;
    let lowered = if let Some(TypedInput::Scopes(scopes)) = typed {
        let mut result = Ok(());
        for scope in scopes {
            if !typed_statements_supported(scope.statements) {
                result = Err(error("initializer scopes", "unsupported typed statement"));
                break;
            }
            compiler.bindings = &scope.bindings;
            result = compiler.typed_statements(scope.statements);
            if result.is_err() {
                break;
            }
        }
        result
    } else if let Some(TypedInput::Statements(statements)) = typed {
        if !typed_statements_supported(statements) {
            return Err(vec![error(
                "typed statements",
                "unsupported typed statement",
            )]);
        }
        compiler.typed_statements(statements)
    } else if let Some(TypedInput::Modified(fields)) = typed {
        compiler.modified_fields(fields)
    } else {
        let typed = parse_body_items(body);
        if typed.diagnostics.is_empty() && typed_statements_supported(&typed.statements) {
            compiler.typed_statements(&typed.statements)
        } else {
            compiler.statements(body)
        }
    };
    if let Some(error) = compiler.resolver_failure.take() {
        return Err(vec![error.at(compiler.statement_span)]);
    }
    lowered.map_err(|error| vec![error.at(compiler.statement_span)])?;
    if compiler.debug_current.is_none() {
        compiler.debug_current = compiler.debug_last;
    }
    compiler.emit(opcode::END, vec![]);
    compiler.result.local_count = compiler.locals.len() as u32;
    compiler.result.local_names = compiler.locals;
    compiler.result.argument_names = bindings.parameters.clone();
    compiler.result.argument_type_flags = bindings.parameter_type_flags.clone();
    compiler.result.argument_value_sources = bindings.parameter_value_sources.clone();
    if let Some(lookup) = lookup {
        let mut seen = BTreeSet::new();
        for item in &mut compiler.result.code.items {
            let CodeItem::Instruction(instruction) = item else {
                continue;
            };
            for operand in &mut instruction.operands {
                if let Word::Value(ValueWord::ClassPath { path, .. }) = operand {
                    let runtime_type = lookup.runtime_type(path).map_err(|error| vec![error])?;
                    if runtime_type == *path {
                        if let Some(primitive) = crate::NativePrimitiveType::from_path(path) {
                            seen.insert(path.clone());
                            *operand = Word::Value(ValueWord::PrimitiveType(primitive));
                            continue;
                        }
                    }
                    if runtime_type != *path {
                        let alias = path.clone();
                        if seen.insert(alias.clone()) {
                            compiler.result.instance_paths.push(alias.clone());
                        }
                        *operand = Word::Value(ValueWord::Instance(alias));
                    }
                }
            }
        }
        compiler
            .result
            .class_paths
            .retain(|path| !seen.contains(path));
    } else if let Some(shared) = &bindings.shared {
        compiler
            .result
            .class_paths
            .retain(|path| !shared.modified_instances.contains_key(path));
        let mut seen = BTreeSet::new();
        for item in &mut compiler.result.code.items {
            let CodeItem::Instruction(instruction) = item else {
                continue;
            };
            for operand in &mut instruction.operands {
                if let Word::Value(ValueWord::ClassPath { path, .. }) = operand {
                    if shared.modified_instances.contains_key(path) {
                        let path = path.clone();
                        if seen.insert(path.clone()) {
                            compiler.result.instance_paths.push(path.clone());
                        }
                        *operand = Word::Value(ValueWord::Instance(path));
                    }
                }
            }
        }
    }
    Ok(compiler.result)
}

fn typed_statements_supported(statements: &[Statement]) -> bool {
    statements.iter().all(|statement| match &statement.kind {
        StatementKind::Return(_)
        | StatementKind::Call(_)
        | StatementKind::Expression(_)
        | StatementKind::Assign { .. }
        | StatementKind::Break
        | StatementKind::BreakLabel(_)
        | StatementKind::Continue
        | StatementKind::ContinueLabel(_)
        | StatementKind::Throw(_)
        | StatementKind::Goto(_) => true,
        StatementKind::Label { body, .. } => typed_statements_supported(body),
        StatementKind::Var { declaration, .. } => local_name(declaration).is_some(),
        StatementKind::Set { .. } => true,
        StatementKind::While { body, .. }
        | StatementKind::DoWhile { body, .. }
        | StatementKind::Spawn { body, .. } => typed_statements_supported(body),
        StatementKind::For {
            control: ForControl::All { declaration },
            body,
        } => local_name(declaration).is_some() && typed_statements_supported(body),
        StatementKind::For {
            control: ForControl::Each { binding, .. },
            body,
        } => {
            let binding = binding
                .rsplit_once(" as ")
                .map_or(binding.as_str(), |(name, _)| name.trim());
            (local_name(binding).is_some()
                || (!binding.is_empty()
                    && binding.chars().all(|ch| ch.is_alphanumeric() || ch == '_')))
                && typed_statements_supported(body)
        }
        StatementKind::For {
            control:
                ForControl::Pair {
                    key_binding,
                    value_binding,
                    ..
                },
            body,
        } => {
            [key_binding, value_binding].into_iter().all(|binding| {
                local_name(binding).is_some()
                    || (!binding.is_empty()
                        && binding.chars().all(|ch| ch.is_alphanumeric() || ch == '_'))
            }) && typed_statements_supported(body)
        }
        StatementKind::For {
            control: ForControl::Range { .. },
            body,
        } => typed_statements_supported(body),
        StatementKind::For {
            control: ForControl::CStyle { .. },
            body,
        } => typed_statements_supported(body),
        StatementKind::Switch {
            cases, else_branch, ..
        } => {
            cases
                .iter()
                .all(|case| typed_statements_supported(&case.body))
                && typed_statements_supported(else_branch)
        }
        StatementKind::Try {
            body,
            catch_binding,
            catch_body,
        } => {
            catch_binding
                .as_ref()
                .is_none_or(|binding| local_name(binding).is_some())
                && typed_statements_supported(body)
                && typed_statements_supported(catch_body)
        }
        StatementKind::If {
            then_branch,
            else_branch,
            ..
        } => typed_statements_supported(then_branch) && typed_statements_supported(else_branch),
        _ => false,
    })
}

fn local_name(declaration: &str) -> Option<&str> {
    let raw = declaration
        .strip_prefix("var/")
        .or_else(|| {
            declaration
                .strip_prefix("var")
                .filter(|tail| tail.chars().next().is_some_and(char::is_whitespace))
        })?
        .trim_start();
    if raw.starts_with("static/") || raw.starts_with("global/") {
        return None;
    }
    let raw_name = raw.rsplit('/').next()?;
    let name = raw_name.split_once('[').map_or(raw_name, |(name, _)| name);
    (!name.is_empty() && name.chars().all(|ch| ch.is_alphanumeric() || ch == '_')).then_some(name)
}

fn runtime_declaration_path(path: &str) -> String {
    format!(
        "/{}",
        dm_syntax::project_declaration_type(path)
            .runtime_path
            .trim_start_matches('/')
    )
}

fn local_array_dimensions(declaration: &str) -> Option<Vec<&str>> {
    let raw = declaration.strip_prefix("var/")?;
    let first = raw.find('[')?;
    let mut dimensions = Vec::new();
    let mut depth = 0usize;
    let mut start = 0usize;
    for (offset, ch) in raw.char_indices().skip_while(|(offset, _)| *offset < first) {
        match ch {
            '[' => {
                if depth == 0 {
                    start = offset + 1;
                }
                depth += 1;
            }
            ']' => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    dimensions.push(raw[start..offset].trim());
                }
            }
            _ if depth == 0 => return None,
            _ => {}
        }
    }
    (depth == 0 && !dimensions.is_empty() && dimensions.iter().all(|size| !size.is_empty()))
        .then_some(dimensions)
}

fn is_output_target(expr: &Expr) -> bool {
    matches!(&expr.kind, ExprKind::Ident(name) if name == "world")
        || matches!(
            &expr.kind,
            ExprKind::Member { object, selector, via_colon: false }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "world")
                    && selector == "log"
        )
}

struct Compiler<'a> {
    result: SimpleProc,
    bindings: &'a LowerBindings,
    lookup: Option<&'a crate::lower_resolver::ProjectResolver<'a>>,
    debug: Option<&'a dyn DebugSourceProvider>,
    debug_current: Option<u32>,
    debug_last: Option<u32>,
    statement_span: Option<LowerSpan>,
    // Exact AST node identity, not source-span equality: synthesized expressions
    // can share spans. Only an immediate statement call may discard its result.
    discarded_call_root: Option<*const Expr>,
    // Some legacy syntax fallbacks catch LowerError. Semantic query failures
    // survive those fallbacks and prevent any successful lowered result.
    resolver_failure: std::cell::RefCell<Option<LowerError>>,
    locals: Vec<String>,
    local_slots: HashMap<String, u32>,
    local_types: HashMap<String, String>,
    seen_strings: BTreeSet<String>,
    seen_classes: BTreeSet<String>,
    seen_resources: BTreeSet<String>,
    next_label: u32,
    label_try_depths: HashMap<String, usize>,
    user_labels: HashMap<String, String>,
    user_label_iterator_depths: HashMap<String, usize>,
    label_breaks: HashMap<String, String>,
    label_loop_depths: HashMap<String, usize>,
    label_iterator_depths: HashMap<String, usize>,
    try_depth: usize,
    /// (continue target, break target) for nested loops.
    loops: Vec<(String, String)>,
    breaks: Vec<String>,
    iterator_depth: usize,
}

impl Compiler<'_> {
    fn debug_at(&mut self, offset: usize, raw: &str) -> Result<(), LowerError> {
        self.statement_span = Some(LowerSpan {
            start: offset,
            end: offset + raw.len(),
        });
        if let Some(provider) = self.debug {
            let ordinal = provider
                .ordinal(offset)
                .map_err(|reason| error(raw, &reason))?;
            self.debug_current = Some(ordinal);
        }
        Ok(())
    }
    fn class_tag(&self, path: &str) -> Result<Option<u8>, LowerError> {
        let Some(lookup) = self.lookup else {
            return Ok(class_tag(path));
        };
        let runtime_type = self.semantic(lookup.runtime_type(path))?;
        let query = dm_ir::ResolveQuery::Ancestry(dm_ir::SymbolId::of(&runtime_type));
        match self.semantic(lookup.answer(query))? {
            dm_ir::ResolvedMeaning::Missing => Ok(None),
            dm_ir::ResolvedMeaning::Symbols(ancestors) => {
                for ancestor in ancestors {
                    let name = self.semantic(lookup.text(query, ancestor))?;
                    if name.trim_start_matches('/').contains('/') {
                        continue;
                    }
                    if let Some(tag) = class_tag(&name) {
                        return Ok(Some(tag));
                    }
                }
                Ok(None)
            }
            _ => self.semantic(Err(lookup.error(query, "invalid ancestry answer"))),
        }
    }
    fn semantic<T>(&self, result: Result<T, LowerError>) -> Result<T, LowerError> {
        let result = result.map_err(|error| error.at(self.statement_span));
        if let Err(error) = &result {
            self.resolver_failure
                .borrow_mut()
                .get_or_insert_with(|| error.clone());
        }
        result
    }
    fn has_field(&self, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => {
                // Captured lexical statics shadow instance fields. Resolve this
                // before a class-storage query, whose intrinsic coverage may be partial.
                if self
                    .semantic(lookup.procedure_static(self.bindings.procedure_identity, name))?
                    .is_some()
                {
                    return Ok(false);
                }
                match &self.bindings.current_type_path {
                    Some(owner) => {
                        if self.member_global(owner, name)?.is_some() {
                            return Ok(false);
                        }
                        self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                            owner: dm_ir::SymbolId::of(owner),
                            name: dm_ir::SymbolId::of(name),
                        }))
                    }
                    None => Ok(false),
                }
            }
            None => Ok(self.bindings.has_field(name)),
        }
    }
    fn has_global(&self, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(
                lookup.presence(dm_ir::ResolveQuery::GlobalVar(dm_ir::SymbolId::of(name))),
            ),
            None => Ok(self.bindings.has_global(name)),
        }
    }
    fn has_global_proc(&self, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(
                lookup.presence(dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of(name))),
            ),
            None => Ok(self.bindings.has_global_proc(name)),
        }
    }
    fn has_visible_global(&self, name: &str) -> Result<bool, LowerError> {
        if let Some(lookup) = self.lookup {
            if self
                .semantic(lookup.procedure_static(self.bindings.procedure_identity, name))?
                .is_some()
            {
                return Ok(true);
            }
        }
        if self.lookup.is_some() {
            if let Some(owner) = self.bindings.current_type_path.as_deref() {
                if self.member_global(owner, name)?.is_some() {
                    return Ok(true);
                }
            }
        }
        self.has_global(name)
    }
    fn field_type(&self, name: &str) -> Result<Option<String>, LowerError> {
        match (self.lookup, self.bindings.current_type_path.as_deref()) {
            (Some(lookup), Some(owner)) => {
                self.semantic(lookup.declared_type(dm_ir::ResolveQuery::DeclaredVarType {
                    owner: dm_ir::SymbolId::of(owner),
                    name: dm_ir::SymbolId::of(name),
                }))
            }
            (Some(_), None) => Ok(None),
            (None, _) => Ok(self.bindings.field_type(name).map(str::to_owned)),
        }
    }
    fn global_type(&self, name: &str) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(
                lookup.declared_type(dm_ir::ResolveQuery::GlobalVar(dm_ir::SymbolId::of(name))),
            ),
            None => Ok(self.bindings.global_type(name).map(str::to_owned)),
        }
    }
    fn member_type(&self, owner: &str, name: &str) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(lookup) => {
                self.semantic(lookup.declared_type(dm_ir::ResolveQuery::DeclaredVarType {
                    owner: dm_ir::SymbolId::of(owner),
                    name: dm_ir::SymbolId::of(name),
                }))
            }
            None => Ok(self.bindings.member_type(owner, name).map(str::to_owned)),
        }
    }
    fn member_global(&self, owner: &str, name: &str) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.slot(dm_ir::ResolveQuery::VarStorage {
                owner: dm_ir::SymbolId::of(owner),
                name: dm_ir::SymbolId::of(name),
            })),
            None => Ok(self.bindings.member_global(owner, name).map(str::to_owned)),
        }
    }
    fn unique_member_global(&self, name: &str) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.slot(dm_ir::ResolveQuery::UniqueStaticVar(
                dm_ir::SymbolId::of(name),
            ))),
            None => Ok(self.bindings.unique_member_global(name).map(str::to_owned)),
        }
    }
    fn fallback_member_global(
        &self,
        object: &Expr,
        name: &str,
        via_colon: bool,
    ) -> Result<Option<String>, LowerError> {
        if via_colon {
            return Ok(None);
        }
        if let Some(lookup) = self.lookup {
            if let Some(owner) = self.inferred_expression_type(object)? {
                let query = dm_ir::ResolveQuery::VarStorage {
                    owner: dm_ir::SymbolId::of(&owner),
                    name: dm_ir::SymbolId::of(name),
                };
                match self.semantic(lookup.answer(query))? {
                    dm_ir::ResolvedMeaning::InstanceField { .. } => return Ok(None),
                    dm_ir::ResolvedMeaning::Slot { .. } => {
                        return self.semantic(lookup.slot(query))
                    }
                    dm_ir::ResolvedMeaning::Missing => (),
                    _ => return Err(error("member selector", "invalid variable storage answer")),
                }
            }
        }
        self.unique_member_global(name)
    }
    fn member_proc(&self, owner: &str, name: &str) -> Result<Option<String>, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.member_proc(owner, name)),
            None => Ok(self.bindings.member_proc(owner, name).map(str::to_owned)),
        }
    }
    fn has_declared_member_proc(&self, owner: &str, name: &str) -> Result<bool, LowerError> {
        match self.lookup {
            Some(lookup) => self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberProc {
                owner: dm_ir::SymbolId::of(owner),
                name: dm_ir::SymbolId::of(name),
            })),
            None => Ok(self.bindings.has_declared_member_proc(owner, name)),
        }
    }
    fn numeric_constant(&self, name: &str) -> Result<Option<u32>, LowerError> {
        if let Some(lookup) = self.lookup {
            return match self.semantic(lookup.constant(name))? {
                Some(dm_ir::SemanticValue::NumberBits(bits)) => Ok(Some(bits)),
                Some(dm_ir::SemanticValue::Text(_)) | None => Ok(None),
                _ => self.semantic(Err(lookup.error(
                    dm_ir::ResolveQuery::PredefinedConstant(dm_ir::SymbolId::of(name)),
                    "unsupported predefined constant value",
                ))),
            };
        }
        Ok(self
            .bindings
            .shared
            .as_ref()
            .and_then(|shared| shared.numeric_constants.get(name))
            .copied())
    }
    fn string_constant(&self, name: &str) -> Result<Option<String>, LowerError> {
        if let Some(lookup) = self.lookup {
            return match self.semantic(lookup.constant(name))? {
                Some(dm_ir::SemanticValue::Text(bytes)) => {
                    self.semantic(String::from_utf8(bytes.to_vec()).map(Some).map_err(|_| {
                        lookup.error(
                            dm_ir::ResolveQuery::PredefinedConstant(dm_ir::SymbolId::of(name)),
                            "predefined constant is not UTF-8",
                        )
                    }))
                }
                Some(dm_ir::SemanticValue::NumberBits(_)) | None => Ok(None),
                _ => self.semantic(Err(lookup.error(
                    dm_ir::ResolveQuery::PredefinedConstant(dm_ir::SymbolId::of(name)),
                    "unsupported predefined constant value",
                ))),
            };
        }
        Ok(self
            .bindings
            .shared
            .as_ref()
            .and_then(|shared| shared.string_constants.get(name))
            .cloned())
    }
    fn prepare_user_labels(
        &mut self,
        statements: &[Statement],
        depth: usize,
    ) -> Result<(), LowerError> {
        let mut seen = BTreeSet::new();
        for statement in statements {
            if let StatementKind::Label { name, .. } = &statement.kind {
                if name.is_empty()
                    || !name.chars().all(|ch| ch.is_alphanumeric() || ch == '_')
                    || !seen.insert(name.clone())
                {
                    let mut failure = error(&statement.raw_header, "invalid or duplicate label")
                        .at(Some(LowerSpan {
                            start: statement.header_span.start,
                            end: statement.header_span.end,
                        }));
                    failure.kind = LowerErrorKind::SourceError;
                    return Err(failure);
                }
                let label = self.label();
                self.label_try_depths.insert(label.clone(), depth);
                self.user_labels.insert(name.clone(), label);
                self.user_label_iterator_depths
                    .insert(name.clone(), self.iterator_depth);
            }
        }
        Ok(())
    }

    fn typed_statements(&mut self, statements: &[Statement]) -> Result<(), LowerError> {
        let saved_debug = self.debug_current;
        let saved_span = self.statement_span;
        let saved_slots = self.local_slots.clone();
        let saved_types = self.local_types.clone();
        let saved_labels = self.user_labels.clone();
        let saved_label_iterator_depths = self.user_label_iterator_depths.clone();
        let saved_breaks = self.label_breaks.clone();
        let saved_depths = self.label_loop_depths.clone();
        let saved_iterator_depths = self.label_iterator_depths.clone();
        let result = self
            .prepare_user_labels(statements, self.try_depth)
            .and_then(|()| self.typed_statements_inner(statements))
            .map_err(|error| error.at(self.statement_span));
        self.debug_current = saved_debug;
        self.statement_span = saved_span;
        self.local_slots = saved_slots;
        self.local_types = saved_types;
        self.user_labels = saved_labels;
        self.user_label_iterator_depths = saved_label_iterator_depths;
        self.label_breaks = saved_breaks;
        self.label_loop_depths = saved_depths;
        self.label_iterator_depths = saved_iterator_depths;
        result
    }

    fn typed_statements_inner(&mut self, statements: &[Statement]) -> Result<(), LowerError> {
        for statement in statements {
            let scoped_statement = matches!(
                &statement.kind,
                StatementKind::For { .. } | StatementKind::Try { .. }
            );
            let saved_slots = scoped_statement.then(|| self.local_slots.clone());
            let saved_types = scoped_statement.then(|| self.local_types.clone());
            self.debug_at(statement.header_span.start, &statement.raw_header)?;
            match &statement.kind {
                StatementKind::Set { .. } => {
                    return Err(error(
                        &statement.raw_header,
                        "procedure setting was not normalized",
                    ));
                }
                StatementKind::Return(None) => self.emit(opcode::END, vec![]),
                StatementKind::Return(Some(value)) => {
                    self.expression(value, &statement.raw_header)?;
                    self.emit(opcode::RET, vec![]);
                }
                StatementKind::Throw(value) => {
                    self.expression(value, &statement.raw_header)?;
                    self.emit(0x12d, vec![]);
                }
                StatementKind::Label { name, body } => {
                    let label = self
                        .user_labels
                        .get(name)
                        .ok_or_else(|| error(&statement.raw_header, "undefined label"))?
                        .clone();
                    self.result.code.items.push(CodeItem::Label(label));
                    let end = self.label();
                    let prior_break = self.label_breaks.insert(name.clone(), end.clone());
                    let prior_depth = self
                        .label_loop_depths
                        .insert(name.clone(), self.loops.len());
                    let is_iterator_loop = body.first().is_some_and(|statement| {
                        matches!(
                            &statement.kind,
                            StatementKind::For {
                                control: ForControl::Each { .. }
                                    | ForControl::Pair { .. }
                                    | ForControl::All { .. },
                                ..
                            }
                        )
                    });
                    let target_iterator_depth = self.iterator_depth + usize::from(is_iterator_loop);
                    let prior_iterator_depth = self
                        .label_iterator_depths
                        .insert(name.clone(), target_iterator_depth);
                    self.typed_statements(body)?;
                    if let Some(prior) = prior_break {
                        self.label_breaks.insert(name.clone(), prior);
                    } else {
                        self.label_breaks.remove(name);
                    }
                    if let Some(prior) = prior_depth {
                        self.label_loop_depths.insert(name.clone(), prior);
                    } else {
                        self.label_loop_depths.remove(name);
                    }
                    if let Some(prior) = prior_iterator_depth {
                        self.label_iterator_depths.insert(name.clone(), prior);
                    } else {
                        self.label_iterator_depths.remove(name);
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Goto(name) => {
                    let label = self
                        .user_labels
                        .get(name)
                        .ok_or_else(|| error(&statement.raw_header, "undefined goto label"))?
                        .clone();
                    let depth = *self.label_try_depths.get(&label).unwrap_or(&0);
                    if depth > self.try_depth {
                        return Err(error(
                            &statement.raw_header,
                            "goto into protected try body is unsupported",
                        ));
                    }
                    let target_iterator_depth =
                        *self.user_label_iterator_depths.get(name).ok_or_else(|| {
                            error(
                                &statement.raw_header,
                                "goto label iterator depth is unknown",
                            )
                        })?;
                    if target_iterator_depth > self.iterator_depth {
                        return Err(error(
                            &statement.raw_header,
                            "goto into iterator body is unsupported",
                        ));
                    }
                    for _ in target_iterator_depth.max(1)..self.iterator_depth {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    self.emit(
                        if depth < self.try_depth {
                            0x12f
                        } else if self.iterator_depth > 0 {
                            opcode::JMP_LOOP
                        } else {
                            opcode::JMP
                        },
                        vec![Word::Branch(label)],
                    );
                }
                StatementKind::Call(value) if matches!(&value.kind, ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "sleep") && args.len() == 1) =>
                {
                    let ExprKind::Call { args, .. } = &value.kind else {
                        unreachable!()
                    };
                    self.expression(&args[0], &statement.raw_header)?;
                    self.emit(opcode::SLEEP, vec![]);
                }
                StatementKind::Call(value) if matches!(&value.kind, ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "del") && args.len() == 1) =>
                {
                    let ExprKind::Call { args, .. } = &value.kind else {
                        unreachable!()
                    };
                    self.expression(&args[0], &statement.raw_header)?;
                    self.emit(0x0c, vec![]);
                }
                StatementKind::Expression(value) if matches!(&value.kind, ExprKind::Binary { op, .. } if op == "<<") =>
                {
                    self.output_statement(value, &statement.raw_header)?;
                }
                StatementKind::Call(value) | StatementKind::Expression(value) => {
                    if self.crash_statement(value, &statement.raw_header)? {
                        continue;
                    }
                    if self.output_statement(value, &statement.raw_header)? {
                        continue;
                    }
                    if self.builtin_statement(value, &statement.raw_header)? {
                        continue;
                    }
                    if let ExprKind::Binary { op, lhs, rhs } = &value.kind {
                        if op == "||=" || op == "&&=" {
                            self.assign_expr(lhs, op, rhs, &statement.raw_header)?;
                            continue;
                        }
                    }
                    if let ExprKind::Unary { op, value } = &value.kind {
                        if matches!(op.as_str(), "post++" | "post--" | "pre++" | "pre--") {
                            self.inc_dec(
                                value,
                                if op.ends_with("++") { 0x66 } else { 0x67 },
                                &statement.raw_header,
                            )?;
                            continue;
                        }
                    }
                    self.discarded_expression(value, &statement.raw_header)?;
                }
                StatementKind::Assign { target, op, value } => {
                    self.assign_expr(target, op, value, &statement.raw_header)?;
                }
                StatementKind::Var { declaration, value } => {
                    let name = local_name(declaration).ok_or_else(|| {
                        error(&statement.raw_header, "unsupported local declaration")
                    })?;
                    if name.is_empty() || self.local_slots.contains_key(name) {
                        return Err(error(
                            &statement.raw_header,
                            "unsupported or repeated local declaration",
                        ));
                    }
                    let slot = self.locals.len() as u32;
                    self.locals.push(name.into());
                    self.local_slots.insert(name.into(), slot);
                    if let Some(dimensions) = local_array_dimensions(declaration) {
                        if value.is_some() {
                            return Err(error(
                                &statement.raw_header,
                                "array declaration cannot have an initializer",
                            ));
                        }
                        self.local_array(&dimensions, &statement.raw_header)?;
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                        continue;
                    }
                    if let Some((path, _)) = declaration
                        .strip_prefix("var/")
                        .and_then(|raw| raw.rsplit_once('/'))
                    {
                        self.local_types
                            .insert(name.into(), runtime_declaration_path(path));
                    } else if declaration.trim_end().ends_with("[]") {
                        self.local_types.insert(name.into(), "/list".into());
                    }
                    if let Some(value) = value {
                        self.local_initializer(value, declaration, &statement.raw_header)?;
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                    } else if !self.loops.is_empty() {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                    }
                }
                StatementKind::While { condition, body } => {
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.condition(condition, &statement.raw_header)?;
                    self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                    self.loops.push((start.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.typed_statements(body);
                    self.loops.pop();
                    self.breaks.pop();
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::DoWhile { body, condition } => {
                    let start = self.label();
                    let continue_label = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.loops.push((continue_label.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.typed_statements(body);
                    self.loops.pop();
                    self.breaks.pop();
                    result?;
                    self.result.code.items.push(CodeItem::Label(continue_label));
                    self.condition(condition, &statement.raw_header)?;
                    self.emit(0xf9, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Spawn { delay, body } => {
                    if let Some(delay) = delay {
                        self.expression(delay, &statement.raw_header)?;
                    } else {
                        self.emit(opcode::PUSH_INT, vec![Word::Immediate(0)]);
                    }
                    let end = self.label();
                    self.emit(0x25, vec![Word::Branch(end.clone())]);
                    self.typed_statements(body)?;
                    self.emit(opcode::END, vec![]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::For {
                    control: ForControl::All { declaration },
                    body,
                } => {
                    let name = local_name(declaration).ok_or_else(|| {
                        error(&statement.raw_header, "world iterator must declare a local")
                    })?;
                    let raw = declaration.strip_prefix("var/").ok_or_else(|| {
                        error(&statement.raw_header, "world iterator requires a type")
                    })?;
                    let (type_name, _) = raw.rsplit_once('/').ok_or_else(|| {
                        error(&statement.raw_header, "world iterator requires a type")
                    })?;
                    let path = runtime_declaration_path(type_name);
                    let tag = self.class_tag(&path)?.ok_or_else(|| {
                        error(&statement.raw_header, "unsupported world iterator type")
                    })?;
                    if self.local_slots.contains_key(name) {
                        return Err(error(&statement.raw_header, "repeated iterator binding"));
                    }
                    let slot = self.locals.len() as u32;
                    self.locals.push(name.into());
                    self.local_slots.insert(name.into(), slot);
                    self.local_types.insert(name.into(), path.clone());
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::World)]);
                    if self.seen_classes.insert(path.clone()) {
                        self.result.class_paths.push(path.clone());
                    }
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ClassPath { path, tag })],
                    );
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(5), Word::Immediate(0x4000)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                    self.iterator_depth += 1;
                    self.loops.push((start.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                }
                StatementKind::For {
                    control: ForControl::Each { binding, iterable },
                    body,
                } => {
                    let (binding, explicit_mask) =
                        if let Some((name, filter)) = binding.rsplit_once(" as ") {
                            let mask = filter
                                .split('|')
                                .map(str::trim)
                                .try_fold(0u32, |mask, part| {
                                    Some(
                                        mask | match part {
                                            "anything" => 0x1000,
                                            "mob" => 1,
                                            "obj" => 2,
                                            "turf" => 32,
                                            _ => return None,
                                        },
                                    )
                                })
                                .ok_or_else(|| {
                                    error(&statement.raw_header, "unsupported iterator type filter")
                                })?;
                            (name.trim(), Some(mask))
                        } else {
                            (binding.trim(), None)
                        };
                    let mask = explicit_mask.unwrap_or_else(|| {
                        let path = binding.strip_prefix("var/").unwrap_or(binding);
                        match path.split('/').next().unwrap_or("") {
                            "mob" => 1,
                            "obj" => 2,
                            "turf" => 32,
                            _ => 0,
                        }
                    });
                    let binding_variable = if let Some(name) = local_name(binding) {
                        if self.local_slots.contains_key(name) {
                            return Err(error(&statement.raw_header, "repeated iterator binding"));
                        }
                        let slot = self.locals.len() as u32;
                        self.locals.push(name.into());
                        self.local_slots.insert(name.into(), slot);
                        if let Some((path, _)) = binding
                            .strip_prefix("var/")
                            .and_then(|raw| raw.rsplit_once('/'))
                        {
                            self.local_types
                                .insert(name.into(), runtime_declaration_path(path));
                        }
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                        VariableWord::Local(slot)
                    } else {
                        self.variable(binding, &statement.raw_header)?
                    };
                    self.ensure_writable(&binding_variable, &statement.raw_header)?;
                    self.expression(iterable, &statement.raw_header)?;
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(5), Word::Immediate(mask)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(binding_variable.clone())],
                    );
                    self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                    if mask == 0
                        || (explicit_mask.is_none()
                            && binding
                                .strip_prefix("var/")
                                .and_then(|raw| raw.rsplit_once('/'))
                                .is_some_and(|(path, _)| path.contains('/')))
                    {
                        if let Some((type_name, _)) = binding
                            .strip_prefix("var/")
                            .and_then(|raw| raw.rsplit_once('/'))
                        {
                            let path = runtime_declaration_path(type_name);
                            let tag = self.class_tag(&path)?.ok_or_else(|| {
                                error(&statement.raw_header, "unsupported iterator type")
                            })?;
                            if self.seen_classes.insert(path.clone()) {
                                self.result.class_paths.push(path.clone());
                            }
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(binding_variable.clone())],
                            );
                            self.emit(
                                opcode::PUSH_VAL,
                                vec![Word::Value(ValueWord::ClassPath { path, tag })],
                            );
                            self.emit(0x7d, vec![]);
                            self.emit(opcode::TEST, vec![]);
                            self.emit(0xfa, vec![Word::Branch(start.clone())]);
                        }
                    }
                    self.iterator_depth += 1;
                    self.loops.push((start.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                }
                StatementKind::For {
                    control:
                        ForControl::Pair {
                            key_binding,
                            value_binding,
                            iterable,
                        },
                    body,
                } => {
                    let mut pair = Vec::with_capacity(2);
                    for binding in [key_binding, value_binding] {
                        let name = local_name(binding).unwrap_or(binding);
                        let variable = if binding.starts_with("var/")
                            || (!self.local_slots.contains_key(name)
                                && !self.bindings.parameters.iter().any(|param| param == name))
                        {
                            if self.local_slots.contains_key(name) {
                                return Err(error(
                                    &statement.raw_header,
                                    "repeated iterator binding",
                                ));
                            }
                            let slot = self.locals.len() as u32;
                            self.locals.push(name.into());
                            self.local_slots.insert(name.into(), slot);
                            if let Some((path, _)) = binding
                                .strip_prefix("var/")
                                .and_then(|raw| raw.rsplit_once('/'))
                            {
                                self.local_types
                                    .insert(name.into(), runtime_declaration_path(path));
                            }
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                            self.emit(
                                opcode::SET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            VariableWord::Local(slot)
                        } else {
                            self.variable(name, &statement.raw_header)?
                        };
                        self.ensure_writable(&variable, &statement.raw_header)?;
                        pair.push(variable);
                    }
                    self.expression(iterable, &statement.raw_header)?;
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(20), Word::Immediate(0)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(0x17e, vec![Word::Variable(pair[1].clone())]);
                    self.emit(opcode::SET_VAR, vec![Word::Variable(pair[0].clone())]);
                    self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                    self.iterator_depth += 1;
                    self.loops.push((start.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                }
                StatementKind::For {
                    control:
                        ForControl::Range {
                            binding,
                            start,
                            end,
                            step,
                        },
                    body,
                } => {
                    if step
                        .as_ref()
                        .and_then(fold_number)
                        .is_some_and(|value| !value.is_finite() || value == 0.0)
                    {
                        return Err(error(
                            &statement.raw_header,
                            "range step must be finite and nonzero",
                        ));
                    }
                    let binding_name = if binding.starts_with("var/") {
                        let name = local_name(binding).ok_or_else(|| {
                            error(&statement.raw_header, "unsupported range binding")
                        })?;
                        if self.local_slots.contains_key(name) {
                            return Err(error(&statement.raw_header, "repeated range binding"));
                        }
                        let slot = self.locals.len() as u32;
                        self.locals.push(name.into());
                        self.local_slots.insert(name.into(), slot);
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                        name
                    } else {
                        binding.as_str()
                    };
                    let binding_variable = self.variable(binding_name, &statement.raw_header)?;
                    self.ensure_writable(&binding_variable, &statement.raw_header)?;
                    self.expression(start, &statement.raw_header)?;
                    self.expression(end, &statement.raw_header)?;
                    if let Some(step) = step {
                        self.expression(step, &statement.raw_header)?;
                    }
                    // Native range state assigns the visible binding only when
                    // entering an iteration. Empty ranges preserve its value,
                    // and completion preserves the last body assignment.
                    self.emit(if step.is_some() { 0xfe } else { 0xfc }, vec![]);
                    let loop_start = self.label();
                    let loop_end = self.label();
                    self.result
                        .code
                        .items
                        .push(CodeItem::Label(loop_start.clone()));
                    self.emit(
                        if step.is_some() { 0xff } else { 0xfd },
                        vec![
                            Word::Branch(loop_end.clone()),
                            Word::Variable(binding_variable),
                        ],
                    );
                    self.loops.push((loop_start.clone(), loop_end.clone()));
                    self.breaks.push(loop_end.clone());
                    let result = self.typed_statements(body);
                    self.breaks.pop();
                    self.loops.pop();
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(loop_start)]);
                    self.result.code.items.push(CodeItem::Label(loop_end));
                    self.emit(
                        0xfb,
                        vec![Word::Immediate(if step.is_some() { 3 } else { 2 })],
                    );
                }
                StatementKind::For {
                    control:
                        ForControl::CStyle {
                            initializer,
                            condition,
                            step,
                        },
                    body,
                } => {
                    if let Some(initializer) = initializer {
                        match initializer {
                            ForInitializer::Declare { declaration, value } => {
                                let name = local_name(declaration).ok_or_else(|| {
                                    error(
                                        &statement.raw_header,
                                        "unsupported for initializer declaration",
                                    )
                                })?;
                                if self.local_slots.contains_key(name) {
                                    return Err(error(
                                        &statement.raw_header,
                                        "repeated for initializer local",
                                    ));
                                }
                                let slot = self.locals.len() as u32;
                                self.locals.push(name.into());
                                self.local_slots.insert(name.into(), slot);
                                if let Some(value) = value {
                                    self.expression(value, &statement.raw_header)?;
                                    self.emit(
                                        opcode::SET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                }
                            }
                            ForInitializer::Expr(value) => {
                                self.expression_statement(value, &statement.raw_header)?
                            }
                        }
                    }
                    let start = self.label();
                    let increment = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    if let Some(condition) = condition {
                        self.condition(condition, &statement.raw_header)?;
                        self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                    }
                    self.loops.push((increment.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.typed_statements(body);
                    self.loops.pop();
                    self.breaks.pop();
                    result?;
                    self.result.code.items.push(CodeItem::Label(increment));
                    if let Some(step) = step {
                        self.expression_statement(step, &statement.raw_header)?;
                    }
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Switch {
                    selector,
                    cases,
                    else_branch,
                } => {
                    let slot = self.locals.len() as u32;
                    let name = format!("__dmb_switch_{slot}");
                    self.locals.push(name.clone());
                    self.local_slots.insert(name, slot);
                    self.expression(selector, &statement.raw_header)?;
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    let end = self.label();
                    for case in cases {
                        let matched = self.label();
                        let next = self.label();
                        for alternative in &case.alternatives {
                            match alternative {
                                SwitchAlternative::Exact(value) => {
                                    self.emit(
                                        opcode::GET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                    self.expression(value, &statement.raw_header)?;
                                    self.emit(opcode::TEQ, vec![]);
                                    self.emit(opcode::POP, vec![]);
                                    self.emit(opcode::JNZ, vec![Word::Branch(matched.clone())]);
                                }
                                SwitchAlternative::Range(lower, upper) => {
                                    let after = self.label();
                                    self.emit(
                                        opcode::GET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                    self.expression(lower, &statement.raw_header)?;
                                    self.emit(opcode::TGE, vec![]);
                                    self.emit(opcode::TEST, vec![]);
                                    self.emit(opcode::JZ, vec![Word::Branch(after.clone())]);
                                    self.emit(
                                        opcode::GET_VAR,
                                        vec![Word::Variable(VariableWord::Local(slot))],
                                    );
                                    self.expression(upper, &statement.raw_header)?;
                                    self.emit(opcode::TLE, vec![]);
                                    self.emit(opcode::TEST, vec![]);
                                    self.emit(opcode::JNZ, vec![Word::Branch(matched.clone())]);
                                    self.result.code.items.push(CodeItem::Label(after));
                                }
                            }
                        }
                        self.emit(opcode::JMP, vec![Word::Branch(next.clone())]);
                        self.result.code.items.push(CodeItem::Label(matched));
                        self.typed_statements(&case.body)?;
                        self.emit(opcode::JMP, vec![Word::Branch(end.clone())]);
                        self.result.code.items.push(CodeItem::Label(next));
                    }
                    self.typed_statements(else_branch)?;
                    self.result.code.items.push(CodeItem::Label(end));
                }
                StatementKind::Try {
                    body,
                    catch_binding,
                    catch_body,
                } => {
                    let catch_label = self.label();
                    let end_label = self.label();
                    self.emit(0x12c, vec![Word::Branch(catch_label.clone())]);
                    self.try_depth += 1;
                    let protected = self.typed_statements(body);
                    self.try_depth -= 1;
                    protected?;
                    self.emit(0x12e, vec![Word::Branch(end_label.clone())]);
                    self.result.code.items.push(CodeItem::Label(catch_label));
                    if let Some(binding) = catch_binding {
                        let name = local_name(binding).ok_or_else(|| {
                            error(&statement.raw_header, "unsupported catch binding")
                        })?;
                        if self.local_slots.contains_key(name) {
                            return Err(error(&statement.raw_header, "repeated catch binding"));
                        }
                        let slot = self.locals.len() as u32;
                        self.locals.push(name.into());
                        self.local_slots.insert(name.into(), slot);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Local(slot))],
                        );
                    } else {
                        self.emit(opcode::POP, vec![]);
                    }
                    self.typed_statements(catch_body)?;
                    self.result.code.items.push(CodeItem::Label(end_label));
                }
                StatementKind::Break => {
                    let target = self
                        .breaks
                        .last()
                        .ok_or_else(|| error(&statement.raw_header, "break outside loop"))?
                        .clone();
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    self.emit(
                        if leaves_try { 0x12e } else { opcode::JMP },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::BreakLabel(name) => {
                    let target = self
                        .label_breaks
                        .get(name)
                        .ok_or_else(|| error(&statement.raw_header, "break label is not active"))?
                        .clone();
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    let target_iterator_depth =
                        *self.label_iterator_depths.get(name).ok_or_else(|| {
                            error(
                                &statement.raw_header,
                                "break label iterator depth is unknown",
                            )
                        })?;
                    for _ in target_iterator_depth.max(1)..self.iterator_depth {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    self.emit(
                        if leaves_try { 0x12e } else { opcode::JMP },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::Continue => {
                    let target = self
                        .loops
                        .last()
                        .ok_or_else(|| error(&statement.raw_header, "continue outside loop"))?
                        .0
                        .clone();
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    self.emit(
                        if leaves_try { 0x12f } else { opcode::JMP_LOOP },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::ContinueLabel(name) => {
                    let depth = *self.label_loop_depths.get(name).ok_or_else(|| {
                        error(&statement.raw_header, "continue label is not active")
                    })?;
                    let target = self
                        .loops
                        .get(depth)
                        .ok_or_else(|| error(&statement.raw_header, "continue label has no loop"))?
                        .0
                        .clone();
                    let leaves_try = self
                        .label_try_depths
                        .get(&target)
                        .is_some_and(|depth| self.try_depth > *depth);
                    let target_iterator_depth =
                        *self.label_iterator_depths.get(name).ok_or_else(|| {
                            error(
                                &statement.raw_header,
                                "continue label iterator depth is unknown",
                            )
                        })?;
                    for _ in target_iterator_depth.max(1)..self.iterator_depth {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    self.emit(
                        if leaves_try { 0x12f } else { opcode::JMP_LOOP },
                        vec![Word::Branch(target)],
                    );
                }
                StatementKind::If {
                    condition,
                    then_branch,
                    else_branch,
                } => {
                    self.condition(condition, &statement.raw_header)?;
                    let else_label = self.label();
                    self.emit(opcode::JZ, vec![Word::Branch(else_label.clone())]);
                    self.typed_statements(then_branch)?;
                    if else_branch.is_empty() {
                        self.result.code.items.push(CodeItem::Label(else_label));
                    } else {
                        let end_label = self.label();
                        self.emit(opcode::JMP, vec![Word::Branch(end_label.clone())]);
                        self.result.code.items.push(CodeItem::Label(else_label));
                        self.typed_statements(else_branch)?;
                        self.result.code.items.push(CodeItem::Label(end_label));
                    }
                }
                _ => {
                    return Err(error(
                        &statement.raw_header,
                        "typed statement is not lowered",
                    ))
                }
            }
            if let Some(saved_slots) = saved_slots {
                self.local_slots = saved_slots;
            }
            if let Some(saved_types) = saved_types {
                self.local_types = saved_types;
            }
        }
        Ok(())
    }
    fn emit(&mut self, opcode: u32, operands: Vec<Word>) {
        // Branch entries must establish their own source before executing.
        if opcode != 0x84
            && opcode != 0x85
            && (self.debug_last != self.debug_current
                || matches!(self.result.code.items.last(), Some(CodeItem::Label(_))))
        {
            if let Some(origin) = self.debug_current {
                self.result
                    .code
                    .items
                    .push(CodeItem::Instruction(Instruction {
                        opcode: 0x84,
                        operands: vec![Word::SourceFile(origin)],
                    }));
                self.result
                    .code
                    .items
                    .push(CodeItem::Instruction(Instruction {
                        opcode: 0x85,
                        operands: vec![Word::SourceLine(origin)],
                    }));
                self.debug_last = Some(origin);
            }
        }
        self.result
            .code
            .items
            .push(CodeItem::Instruction(Instruction { opcode, operands }));
    }

    fn intern_string(&mut self, value: &str) {
        if self.seen_strings.insert(value.to_owned()) {
            self.result.strings.push(value.to_owned());
        }
    }

    fn intern_format_template(&mut self, bytes: Vec<u8>) -> String {
        if let Ok(text) = std::str::from_utf8(&bytes) {
            let key = text.to_owned();
            self.intern_string(&key);
            return key;
        }
        let mut key = String::from("\u{e000}format:");
        for byte in &bytes {
            key.push_str(&format!("{byte:02x}"));
        }
        if self.seen_strings.insert(key.clone()) {
            self.result.strings.push(key.clone());
        }
        self.result.format_templates.insert(key.clone(), bytes);
        key
    }

    fn label(&mut self) -> String {
        let next = self.next_label;
        self.next_label += 1;
        let label = format!("block_{next}");
        self.label_try_depths.insert(label.clone(), self.try_depth);
        label
    }

    fn parameter_defaults(&mut self) -> Result<(), LowerError> {
        if !self.bindings.parameter_type_flags.is_empty()
            && self.bindings.parameter_type_flags.len() != self.bindings.parameters.len()
        {
            return Err(error(
                "parameters",
                "parameter type flag count differs from names",
            ));
        }
        if !self.bindings.parameter_defaults.is_empty()
            && self.bindings.parameter_defaults.len() != self.bindings.parameters.len()
        {
            return Err(error(
                "parameters",
                "parameter default count differs from names",
            ));
        }
        for (index, default) in self.bindings.parameter_defaults.iter().enumerate() {
            let Some(default) = default else {
                continue;
            };
            let slot = Word::Variable(VariableWord::Arg(index as u32));
            self.emit(opcode::GET_VAR, vec![slot.clone()]);
            self.emit(opcode::IS_NULL, vec![]);
            self.emit(opcode::TEST, vec![]);
            let skip = self.label();
            self.emit(opcode::JZ, vec![Word::Branch(skip.clone())]);
            if let Some(path) = self
                .bindings
                .parameter_types
                .get(&self.bindings.parameters[index])
            {
                let parsed = parse_expression(default);
                if !parsed.diagnostics.is_empty() {
                    return Err(error(default, "invalid parameter default expression"));
                }
                let expr = parsed
                    .expr
                    .ok_or_else(|| error(default, "missing parameter default expression"))?;
                self.local_initializer(
                    &expr,
                    &format!("var{path}/{}", self.bindings.parameters[index]),
                    default,
                )?;
            } else {
                self.expression_text(default, default)?;
            }
            self.emit(opcode::SET_VAR, vec![slot]);
            self.result.code.items.push(CodeItem::Label(skip));
        }
        Ok(())
    }

    // Clause ordinals drive the frozen branch construction and labels.
    fn statements(&mut self, body: &[Item]) -> Result<(), LowerError> {
        let saved_debug = self.debug_current;
        let saved_span = self.statement_span;
        let result = self
            .statements_inner(body)
            .map_err(|error| error.at(self.statement_span));
        self.debug_current = saved_debug;
        self.statement_span = saved_span;
        result
    }
    #[allow(clippy::needless_range_loop)]
    fn statements_inner(&mut self, body: &[Item]) -> Result<(), LowerError> {
        let mut index = 0;
        while index < body.len() {
            let item = &body[index];
            self.debug_at(item.header_span.start, &item.header)?;
            let text = item.header.trim();
            if text.starts_with("if(") || text.starts_with("if (") {
                let mut last = index + 1;
                while body
                    .get(last)
                    .is_some_and(|next| next.header.trim().starts_with("else"))
                {
                    last += 1;
                }
                let end_label = self.label();
                for clause_index in index..last {
                    let clause = &body[clause_index];
                    self.debug_at(clause.header_span.start, &clause.header)?;
                    let header = clause.header.trim();
                    let condition = if clause_index == index {
                        header
                    } else if header == "else" {
                        ""
                    } else {
                        header
                            .strip_prefix("else ")
                            .ok_or_else(|| error(header, "unsupported else clause"))?
                    };
                    if !condition.is_empty() {
                        if !(condition.starts_with("if(") || condition.starts_with("if (")) {
                            return Err(error(header, "unsupported else-if condition"));
                        }
                        let expression = parenthesized(condition)
                            .ok_or_else(|| error(header, "malformed if condition"))?;
                        self.expression_text(expression, header)?;
                        self.emit(opcode::TEST, vec![]);
                        let next = self.label();
                        self.emit(opcode::JZ, vec![Word::Branch(next.clone())]);
                        self.statements(&clause.children)?;
                        if clause_index + 1 < last {
                            self.emit(opcode::JMP, vec![Word::Branch(end_label.clone())]);
                        }
                        self.result.code.items.push(CodeItem::Label(next));
                    } else {
                        if clause_index + 1 != last {
                            return Err(error(header, "else must be final"));
                        }
                        self.statements(&clause.children)?;
                    }
                }
                self.result.code.items.push(CodeItem::Label(end_label));
                index = last;
                continue;
            }
            if text.starts_with("while(") || text.starts_with("while (") {
                let condition =
                    parenthesized(text).ok_or_else(|| error(text, "malformed while condition"))?;
                let start_label = self.label();
                let end_label = self.label();
                self.result
                    .code
                    .items
                    .push(CodeItem::Label(start_label.clone()));
                self.expression_text(condition, text)?;
                self.emit(opcode::TEST, vec![]);
                self.emit(opcode::JZ, vec![Word::Branch(end_label.clone())]);
                self.loops.push((start_label.clone(), end_label.clone()));
                self.breaks.push(end_label.clone());
                let body_result = self.statements(&item.children);
                self.loops.pop();
                self.breaks.pop();
                body_result?;
                self.emit(opcode::JMP_LOOP, vec![Word::Branch(start_label)]);
                self.result.code.items.push(CodeItem::Label(end_label));
                index += 1;
                continue;
            }
            if text.starts_with("for(") || text.starts_with("for (") {
                let control =
                    parenthesized(text).ok_or_else(|| error(text, "malformed for control"))?;
                if let Some((binding, iterable)) = control.split_once(" in ") {
                    let binding = binding.trim();
                    let (binding, mask) = binding
                        .strip_suffix(" as anything")
                        .map_or((binding, 0), |name| (name.trim(), 0x1000));
                    let name = binding
                        .strip_prefix("var/")
                        .ok_or_else(|| error(text, "iterator binding must declare a local"))?;
                    if name.is_empty() || name.contains('/') || self.local_slots.contains_key(name)
                    {
                        return Err(error(text, "unsupported iterator binding"));
                    }
                    let slot = self.locals.len() as u32;
                    self.locals.push(name.into());
                    self.local_slots.insert(name.into(), slot);
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.expression_text(iterable.trim(), text)?;
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_PUSH, vec![]);
                    }
                    self.emit(
                        opcode::ITER_LOAD,
                        vec![Word::Immediate(5), Word::Immediate(mask)],
                    );
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.emit(opcode::ITER_NEXT, vec![]);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Local(slot))],
                    );
                    self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                    self.iterator_depth += 1;
                    self.loops.push((start.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.statements(&item.children);
                    self.breaks.pop();
                    self.loops.pop();
                    self.iterator_depth -= 1;
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    if self.iterator_depth > 0 {
                        self.emit(opcode::ITER_POP, vec![]);
                    }
                    index += 1;
                    continue;
                }
                if let Some((begin, remainder)) = control.split_once(" to ") {
                    let (binding, start_value) = begin
                        .split_once('=')
                        .ok_or_else(|| error(text, "range for requires initialized binding"))?;
                    let binding = binding.trim();
                    let (end_value, step_value) = remainder
                        .split_once(" step ")
                        .map_or((remainder.trim(), "1"), |(end, step)| {
                            (end.trim(), step.trim())
                        });
                    let step_number = step_value
                        .parse::<f32>()
                        .map_err(|_| error(text, "range step must be a numeric literal"))?;
                    if !step_number.is_finite() || step_number == 0.0 {
                        return Err(error(text, "range step must be finite and nonzero"));
                    }
                    let name = if let Some(name) = binding.strip_prefix("var/") {
                        let mut declaration = item.clone();
                        declaration.header = format!("var/{name}");
                        declaration.children.clear();
                        self.statement(&declaration)?;
                        name
                    } else {
                        binding
                    };
                    let binding_variable = self.variable(name, text)?;
                    self.ensure_writable(&binding_variable, text)?;
                    self.expression_text(start_value.trim(), text)?;
                    self.expression_text(end_value, text)?;
                    let has_step = remainder.contains(" step ");
                    if has_step {
                        self.expression_text(step_value, text)?;
                    }
                    self.emit(if has_step { 0xfe } else { 0xfc }, vec![]);
                    let start = self.label();
                    let end = self.label();
                    self.result.code.items.push(CodeItem::Label(start.clone()));
                    self.emit(
                        if has_step { 0xff } else { 0xfd },
                        vec![Word::Branch(end.clone()), Word::Variable(binding_variable)],
                    );
                    self.loops.push((start.clone(), end.clone()));
                    self.breaks.push(end.clone());
                    let result = self.statements(&item.children);
                    self.breaks.pop();
                    self.loops.pop();
                    result?;
                    self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                    self.result.code.items.push(CodeItem::Label(end));
                    self.emit(0xfb, vec![Word::Immediate(if has_step { 3 } else { 2 })]);
                    index += 1;
                    continue;
                }
                let parts: Vec<_> = control.split(';').map(str::trim).collect();
                if parts.len() != 3 {
                    return Err(error(
                        text,
                        "only C-style semicolon for loops are supported",
                    ));
                }
                if !parts[0].is_empty() {
                    let mut initializer = item.clone();
                    initializer.header = parts[0].into();
                    initializer.children.clear();
                    self.statement(&initializer)?;
                }
                let start = self.label();
                let step = self.label();
                let end = self.label();
                self.result.code.items.push(CodeItem::Label(start.clone()));
                if !parts[1].is_empty() {
                    self.expression_text(parts[1], text)?;
                    self.emit(opcode::TEST, vec![]);
                    self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                }
                self.loops.push((step.clone(), end.clone()));
                self.breaks.push(end.clone());
                let result = self.statements(&item.children);
                self.loops.pop();
                self.breaks.pop();
                result?;
                self.result.code.items.push(CodeItem::Label(step));
                if !parts[2].is_empty() {
                    let mut increment = item.clone();
                    increment.header = parts[2].into();
                    increment.children.clear();
                    self.statement(&increment)?;
                }
                self.emit(opcode::JMP_LOOP, vec![Word::Branch(start)]);
                self.result.code.items.push(CodeItem::Label(end));
                index += 1;
                continue;
            }
            if text.starts_with("switch(") || text.starts_with("switch (") {
                let selector =
                    parenthesized(text).ok_or_else(|| error(text, "malformed switch selector"))?;
                let slot = self.locals.len() as u32;
                let temp = format!("__dmb_switch_{slot}");
                if self.local_slots.contains_key(&temp) {
                    return Err(error(text, "switch temporary conflicts with local"));
                }
                self.locals.push(temp.clone());
                self.local_slots.insert(temp, slot);
                self.expression_text(selector, text)?;
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Local(slot))],
                );
                let end = self.label();
                for (case_index, case) in item.children.iter().enumerate() {
                    let header = case.header.trim();
                    if header == "else" {
                        if case_index + 1 != item.children.len() {
                            return Err(error(header, "switch else must be final"));
                        }
                        self.statements(&case.children)?;
                        continue;
                    }
                    if !(header.starts_with("if(") || header.starts_with("if (")) {
                        return Err(error(header, "unsupported switch case"));
                    }
                    let value = parenthesized(header)
                        .ok_or_else(|| error(header, "malformed switch case"))?;
                    let matched = self.label();
                    let next = self.label();
                    for alternative in value.split(',').map(str::trim) {
                        if alternative.is_empty() {
                            return Err(error(header, "empty switch alternative"));
                        }
                        if let Some((lower, upper)) = alternative.split_once(" to ") {
                            let after_range = self.label();
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            self.expression_text(lower.trim(), header)?;
                            self.emit(opcode::TGE, vec![]);
                            self.emit(opcode::TEST, vec![]);
                            self.emit(opcode::JZ, vec![Word::Branch(after_range.clone())]);
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            self.expression_text(upper.trim(), header)?;
                            self.emit(opcode::TLE, vec![]);
                            self.emit(opcode::TEST, vec![]);
                            self.emit(opcode::JNZ, vec![Word::Branch(matched.clone())]);
                            self.result.code.items.push(CodeItem::Label(after_range));
                        } else {
                            self.emit(
                                opcode::GET_VAR,
                                vec![Word::Variable(VariableWord::Local(slot))],
                            );
                            self.expression_text(alternative, header)?;
                            self.emit(opcode::TEQ, vec![]);
                            self.emit(opcode::POP, vec![]);
                            self.emit(opcode::JNZ, vec![Word::Branch(matched.clone())]);
                        }
                    }
                    self.emit(opcode::JMP, vec![Word::Branch(next.clone())]);
                    self.result.code.items.push(CodeItem::Label(matched));
                    self.statements(&case.children)?;
                    self.emit(opcode::JMP, vec![Word::Branch(end.clone())]);
                    self.result.code.items.push(CodeItem::Label(next));
                }
                self.result.code.items.push(CodeItem::Label(end));
                index += 1;
                continue;
            }
            self.statement(item)?;
            index += 1;
        }
        Ok(())
    }

    fn statement(&mut self, item: &Item) -> Result<(), LowerError> {
        self.debug_at(item.header_span.start, &item.header)?;
        let text = item.header.trim();
        if text.starts_with("sleep(") && text.ends_with(')') {
            let duration =
                parenthesized(text).ok_or_else(|| error(text, "malformed sleep call"))?;
            self.expression_text(duration, text)?;
            self.emit(opcode::SLEEP, vec![]);
            return Ok(());
        }
        if text == "break" || text == "continue" {
            let target = if text == "break" {
                self.breaks
                    .last()
                    .ok_or_else(|| error(text, "break outside a loop or switch"))?
            } else {
                &self
                    .loops
                    .last()
                    .ok_or_else(|| error(text, "continue outside a loop"))?
                    .0
            }
            .clone();
            self.emit(opcode::JMP, vec![Word::Branch(target)]);
            return Ok(());
        }
        if text == "return" {
            self.emit(opcode::END, vec![]);
            return Ok(());
        }
        if let Some(rest) = text.strip_prefix("return ") {
            self.expression_text(rest, text)?;
            self.emit(opcode::RET, vec![]);
            return Ok(());
        }
        if text.starts_with("var/")
            || text
                .strip_prefix("var")
                .is_some_and(|tail| tail.chars().next().is_some_and(char::is_whitespace))
        {
            let (declaration, initial) = text
                .split_once('=')
                .map_or((text.trim(), None), |(n, e)| (n.trim(), Some(e.trim())));
            let name = local_name(declaration)
                .ok_or_else(|| error(text, "unsupported local declaration"))?;
            if self.local_slots.contains_key(name) {
                return Err(error(text, "unsupported or repeated local declaration"));
            }
            let slot = self.locals.len() as u32;
            self.locals.push(name.into());
            self.local_slots.insert(name.into(), slot);
            if let Some(dimensions) = local_array_dimensions(declaration) {
                if initial.is_some() {
                    return Err(error(text, "array declaration cannot have an initializer"));
                }
                self.local_array(&dimensions, text)?;
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Local(slot))],
                );
                return Ok(());
            }
            if let Some(initial) = initial {
                self.expression_text(initial, text)?;
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Local(slot))],
                );
            } else if !self.loops.is_empty() {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::Local(slot))],
                );
            }
            return Ok(());
        }
        if !item.children.is_empty() {
            return Err(error(text, "control-flow statement is not lowered yet"));
        }
        let parsed = parse_expression(text);
        if !parsed.diagnostics.is_empty() {
            return Err(error(text, "expression syntax is unsupported"));
        }
        let expr = parsed
            .expr
            .ok_or_else(|| error(text, "missing expression"))?;
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if matches!(
                op.as_str(),
                "=" | "+="
                    | "-="
                    | "*="
                    | "/="
                    | "%="
                    | "&="
                    | "|="
                    | "^="
                    | "<<="
                    | ">>="
                    | "||="
                    | "&&="
            ) {
                return self.assign_expr(lhs, op, rhs, text);
            }
        }
        if self.crash_statement(&expr, text)? {
            return Ok(());
        }
        if self.output_statement(&expr, text)? {
            return Ok(());
        }
        if self.builtin_statement(&expr, text)? {
            return Ok(());
        }
        self.expression(&expr, text)?;
        self.emit(opcode::POP, vec![]);
        Ok(())
    }

    fn expression_statement(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        if self.crash_statement(expr, statement)? {
            return Ok(());
        }
        if self.output_statement(expr, statement)? {
            return Ok(());
        }
        if self.builtin_statement(expr, statement)? {
            return Ok(());
        }
        if let ExprKind::Unary { op, value } = &expr.kind {
            if matches!(op.as_str(), "post++" | "post--" | "pre++" | "pre--") {
                return self.inc_dec(
                    value,
                    if op.ends_with("++") { 0x66 } else { 0x67 },
                    statement,
                );
            }
        }
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if matches!(
                op.as_str(),
                "=" | "+="
                    | "-="
                    | "*="
                    | "/="
                    | "%="
                    | "&="
                    | "|="
                    | "^="
                    | "<<="
                    | ">>="
                    | "||="
                    | "&&="
            ) {
                return self.assign_expr(lhs, op, rhs, statement);
            }
        }
        self.discarded_expression(expr, statement)?;
        Ok(())
    }

    fn direct_call_opcode(&self, expr: &Expr) -> u32 {
        if self
            .discarded_call_root
            .is_some_and(|root| std::ptr::eq(root, expr))
        {
            0x2a
        } else {
            opcode::CALL
        }
    }
    fn discarded_expression(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        let previous = self.discarded_call_root.replace(expr);
        let result = self.expression(expr, statement);
        self.discarded_call_root = previous;
        result?;
        if matches!(self.result.code.items.last(), Some(CodeItem::Instruction(instruction)) if instruction.opcode == 0x2a)
        {
            // CallStatement skips one raw word. A source marker must never be
            // inserted between it and this otherwise executable Pop marker.
            self.result
                .code
                .items
                .push(CodeItem::Instruction(Instruction {
                    opcode: opcode::POP,
                    operands: vec![],
                }));
        } else {
            self.emit(opcode::POP, vec![]);
        }
        Ok(())
    }

    fn crash_statement(&mut self, expr: &Expr, statement: &str) -> Result<bool, LowerError> {
        let ExprKind::Call { callee, args } = &expr.kind else {
            return Ok(false);
        };
        if !matches!(&callee.kind, ExprKind::Ident(name) if name == "CRASH") {
            return Ok(false);
        }
        if args.len() > 1 {
            return Err(error(statement, "CRASH expects zero or one argument"));
        }
        if let Some(value) = args.first() {
            self.expression(value, statement)?;
        } else {
            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
        }
        self.emit(0xc7, vec![]);
        Ok(true)
    }

    fn output_statement(&mut self, expr: &Expr, statement: &str) -> Result<bool, LowerError> {
        let ExprKind::Binary { op, lhs, rhs } = &expr.kind else {
            return Ok(false);
        };
        if op == ">>" {
            self.output_receiver(lhs, statement)?;
            self.emit(0xaf, vec![]);
            if let ExprKind::Index { object, index } = &rhs.kind {
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(opcode::LIST_SET, vec![]);
                return Ok(true);
            }
            let variable = match self.variable_expr(rhs, statement) {
                Ok(variable) => variable,
                Err(_) => {
                    let ExprKind::Member {
                        object, selector, ..
                    } = &rhs.kind
                    else {
                        return Err(error(statement, "unsupported read destination"));
                    };
                    self.expression(object, statement)?;
                    self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                    self.intern_string(selector);
                    VariableWord::Field(selector.clone())
                }
            };
            self.ensure_writable(&variable, statement)?;
            self.emit(opcode::SET_VAR, vec![Word::Variable(variable)]);
            return Ok(true);
        }
        if op != "<<" {
            return Ok(false);
        }
        self.output_receiver(lhs, statement)?;
        if let ExprKind::Call { callee, args } = &rhs.kind {
            if let ExprKind::Ident(name) = &callee.kind {
                if name == "load_resource" {
                    if args.len() < 2 {
                        return Err(error(
                            statement,
                            "load_resource expects at least two arguments",
                        ));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x165, vec![Word::Immediate(args.len() as u32 + 1)]);
                    return Ok(true);
                }
                let special = match (name.as_str(), args.len()) {
                    ("run", 1) => Some((0x09, false)),
                    ("link", 1) => Some((0x07, false)),
                    ("browse", 1) => Some((0xaa, false)),
                    ("browse", 2) => Some((0xab, false)),
                    ("browse_rsc", 1..=2) => Some((0x27, args.len() == 1)),
                    ("ftp", 1..=2) => Some((0x08, args.len() == 1)),
                    ("output", 2) => Some((0x10b, false)),
                    _ => None,
                };
                if let Some((opcode, pad_null)) = special {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    if pad_null {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(opcode, vec![]);
                    return Ok(true);
                }
            }
        }
        self.expression(rhs, statement)?;
        self.emit(0x03, vec![]);
        Ok(true)
    }

    fn output_receiver(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        if let ExprKind::Index { object, index } = &expr.kind {
            self.expression(object, statement)?;
            self.expression(index, statement)?;
            self.emit(0xb0, vec![]);
            Ok(())
        } else {
            self.expression(expr, statement)
        }
    }

    fn builtin_statement(&mut self, expr: &Expr, statement: &str) -> Result<bool, LowerError> {
        let ExprKind::Call { callee, args } = &expr.kind else {
            return Ok(false);
        };
        let ExprKind::Ident(name) = &callee.kind else {
            return Ok(false);
        };
        if name == "stat" {
            if !(1..=2).contains(&args.len()) {
                return Err(error(statement, "stat expects one or two arguments"));
            }
            if args.len() == 1 {
                self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x05, vec![]);
            return Ok(true);
        }
        if name == "statpanel" {
            if !(1..=3).contains(&args.len()) {
                return Err(error(statement, "statpanel expects one to three arguments"));
            }
            self.expression(&args[0], statement)?;
            if args.len() == 1 {
                self.emit(0xa2, vec![]);
            } else {
                if args.len() == 2 {
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                }
                for arg in &args[1..] {
                    self.expression(arg, statement)?;
                }
                self.emit(0xa1, vec![]);
            }
            return Ok(true);
        }
        if name == "missile" {
            if args.len() != 3 {
                return Err(error(statement, "missile expects three arguments"));
            }
            for arg in args {
                self.expression(arg, statement)?;
            }
            self.emit(0x0b, vec![]);
            return Ok(true);
        }
        let Some(spec) = crate::builtin_catalog::lookup_with_arity(name, args.len()) else {
            return Ok(false);
        };
        if spec.post_opcode != Some(0x36) && !crate::builtin_catalog::is_void(name) {
            return Ok(false);
        }
        self.expression(expr, statement)?;
        // Expressions materialize the flag or a null value. Native statement
        // calls discard it by omitting that materialization altogether.
        self.result.code.items.pop();
        Ok(true)
    }

    fn assign_expr(
        &mut self,
        target: &Expr,
        op: &str,
        value: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        if op == "||=" || op == "&&=" {
            let variable = self.assignment_variable(target, statement)?;
            self.emit(opcode::GET_VAR, vec![Word::Variable(variable.clone())]);
            self.emit(opcode::TEST, vec![]);
            let end = self.label();
            self.emit(
                if op == "||=" { opcode::JNZ } else { opcode::JZ },
                vec![Word::Branch(end.clone())],
            );
            self.assignment_value_preserving_cache(&variable, value, statement)?;
            self.emit(opcode::SET_VAR, vec![Word::Variable(variable)]);
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if let ExprKind::Index { object, index } = &target.kind {
            if op != "=" {
                let opcode = match op {
                    "+=" => opcode::AUG_ADD,
                    "-=" => opcode::AUG_SUB,
                    "*=" => opcode::AUG_MUL,
                    "/=" => opcode::AUG_DIV,
                    "%=" => opcode::AUG_MOD,
                    "&=" => opcode::AUG_BAND,
                    "|=" => opcode::AUG_BOR,
                    "^=" => opcode::AUG_XOR,
                    "<<=" => 0x4d,
                    ">>=" => 0x4e,
                    _ => return Err(error(statement, "unsupported indexed assignment")),
                };
                self.expression(value, statement)?;
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::CacheKey)],
                );
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.emit(opcode, vec![Word::Variable(VariableWord::CacheIndex)]);
                return Ok(());
            }
        }
        if let ExprKind::SafeMember { object, selector } = &target.kind {
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(318, vec![Word::Branch(end.clone())]);
            self.emit(opcode::PUSH_CACHE, vec![]);
            self.expression(value, statement)?;
            self.emit(opcode::POP_CACHE, vec![]);
            let variable = self
                .expression_member_global(object, selector)?
                .map(|symbol| VariableWord::Global(symbol.to_owned()))
                .unwrap_or_else(|| VariableWord::Field(selector.clone()));
            if matches!(variable, VariableWord::Field(_)) {
                self.intern_string(selector);
            }
            let assignment_opcode = match op {
                "=" => opcode::SET_VAR,
                "+=" => opcode::AUG_ADD,
                "-=" => opcode::AUG_SUB,
                "*=" => opcode::AUG_MUL,
                "/=" => opcode::AUG_DIV,
                "%=" => opcode::AUG_MOD,
                "&=" => opcode::AUG_BAND,
                "|=" => opcode::AUG_BOR,
                "^=" => opcode::AUG_XOR,
                "<<=" => 0x4d,
                ">>=" => 0x4e,
                _ => return Err(error(statement, "unsupported safe member assignment")),
            };
            self.emit(assignment_opcode, vec![Word::Variable(variable)]);
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if let ExprKind::SafeIndex { object, index } = &target.kind {
            self.expression(object, statement)?;
            let end = self.label();
            self.emit(318, vec![Word::Branch(end.clone())]);
            self.emit(opcode::PUSH_CACHE, vec![]);
            self.expression(value, statement)?;
            self.emit(opcode::POP_CACHE, vec![]);
            self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Cache)]);
            self.expression(index, statement)?;
            if op == "=" {
                self.emit(opcode::LIST_SET, vec![]);
            } else {
                let opcode = match op {
                    "+=" => opcode::AUG_ADD,
                    "-=" => opcode::AUG_SUB,
                    "*=" => opcode::AUG_MUL,
                    "/=" => opcode::AUG_DIV,
                    "%=" => opcode::AUG_MOD,
                    "&=" => opcode::AUG_BAND,
                    "|=" => opcode::AUG_BOR,
                    "^=" => opcode::AUG_XOR,
                    "<<=" => 0x4d,
                    ">>=" => 0x4e,
                    _ => return Err(error(statement, "unsupported safe indexed assignment")),
                };
                self.emit(
                    opcode::SET_VAR,
                    vec![Word::Variable(VariableWord::CacheKey)],
                );
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.emit(opcode, vec![Word::Variable(VariableWord::CacheIndex)]);
            }
            self.result.code.items.push(CodeItem::Label(end));
            return Ok(());
        }
        if op == "=" {
            if let ExprKind::Index { object, index } = &target.kind {
                self.expression(value, statement)?;
                self.expression(object, statement)?;
                self.expression(index, statement)?;
                self.emit(opcode::LIST_SET, vec![]);
                return Ok(());
            }
            if let ExprKind::Member {
                object, selector, ..
            } = &target.kind
            {
                if self.variable_expr(target, statement).is_err() {
                    self.expression(value, statement)?;
                    self.expression(object, statement)?;
                    self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                    self.intern_string(selector);
                    self.emit(
                        opcode::SET_VAR,
                        vec![Word::Variable(VariableWord::Field(selector.clone()))],
                    );
                    return Ok(());
                }
            }
            let var = self.variable_expr(target, statement)?;
            self.ensure_writable(&var, statement)?;
            if Self::assignment_needs_target_type(value) {
                if let Some(path) = self.inferred_expression_type(target)? {
                    let declaration = format!("var{path}/__value");
                    self.local_initializer(value, &declaration, statement)?;
                } else {
                    self.expression(value, statement)?;
                }
            } else {
                // This RHS cannot consume the target's declared type. Preserve
                // recursive initializer emission without unrelated metadata IO.
                self.local_initializer(value, "var/__value", statement)?;
            }
            self.emit(opcode::SET_VAR, vec![Word::Variable(var)]);
            return Ok(());
        }
        let opcode = match op {
            "+=" => opcode::AUG_ADD,
            "-=" => opcode::AUG_SUB,
            "*=" => opcode::AUG_MUL,
            "/=" => opcode::AUG_DIV,
            "%=" => opcode::AUG_MOD,
            "&=" => opcode::AUG_BAND,
            "|=" => opcode::AUG_BOR,
            "^=" => opcode::AUG_XOR,
            "<<=" => 0x4d,
            ">>=" => 0x4e,
            _ => return Err(error(statement, "unsupported assignment operator")),
        };
        self.expression(value, statement)?;
        let variable = match self.variable_expr(target, statement) {
            Ok(variable) => variable,
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "unsupported assignment target"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.intern_string(selector);
                VariableWord::Field(selector.clone())
            }
        };
        self.ensure_writable(&variable, statement)?;
        self.emit(opcode, vec![Word::Variable(variable)]);
        Ok(())
    }

    fn expression_text(&mut self, expression: &str, statement: &str) -> Result<(), LowerError> {
        let parsed = parse_expression(expression);
        if !parsed.diagnostics.is_empty() {
            return Err(error(statement, "expression syntax is unsupported"));
        }
        let expression = parsed
            .expr
            .ok_or_else(|| error(statement, "missing expression"))?;
        self.expression(&expression, statement)
    }

    fn variable(&mut self, name: &str, statement: &str) -> Result<VariableWord, LowerError> {
        if let Some(&index) = self.local_slots.get(name) {
            return Ok(VariableWord::Local(index));
        }
        if let Some(index) = self.bindings.parameters.iter().position(|n| n == name) {
            return Ok(VariableWord::Arg(index as u32));
        }
        if let Some(lookup) = self.lookup {
            if let Some(slot) =
                self.semantic(lookup.procedure_static_slot(self.bindings.procedure_identity, name))?
            {
                return Ok(VariableWord::Global(slot));
            }
        }
        if self.lookup.is_some()
            && !matches!(
                name,
                "src" | "usr" | "world" | "args" | "caller" | "callee" | "."
            )
        {
            if let Some(owner) = self.bindings.current_type_path.as_deref() {
                if let Some(slot) = self.member_global(owner, name)? {
                    return Ok(VariableWord::Global(slot));
                }
            }
        }
        match name {
            "src" => Ok(VariableWord::Src),
            "usr" => Ok(VariableWord::Usr),
            "world" => Ok(VariableWord::World),
            "args" => Ok(VariableWord::Args),
            "caller" => Ok(VariableWord::Caller),
            "callee" => Ok(VariableWord::Callee),
            "." => Ok(VariableWord::Dot),
            _ if self.has_field(name)? => {
                self.intern_string(name);
                Ok(VariableWord::SetCache(
                    Box::new(VariableWord::Src),
                    Box::new(VariableWord::Field(name.to_owned())),
                ))
            }
            _ if self.has_global(name)? => {
                if let Some(lookup) = self.lookup {
                    let query = dm_ir::ResolveQuery::VarStorage {
                        owner: dm_ir::SymbolId::of("/"),
                        name: dm_ir::SymbolId::of(name),
                    };
                    let slot = self
                        .semantic(lookup.slot(query))?
                        .ok_or_else(|| error(statement, "global variable has no shared storage"))?;
                    Ok(VariableWord::Global(slot))
                } else {
                    Ok(VariableWord::Global(name.to_owned()))
                }
            }
            _ => Err(error(
                statement,
                &format!("unresolved variable name: {name}"),
            )),
        }
    }

    fn variable_expr(&mut self, expr: &Expr, statement: &str) -> Result<VariableWord, LowerError> {
        match &expr.kind {
            ExprKind::Ident(name) => self.variable(name, statement),
            ExprKind::Group(inner) => self.variable_expr(inner, statement),
            ExprKind::Member {
                object,
                selector,
                via_colon,
            } => {
                if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                    if selector == "vars" {
                        return Ok(VariableWord::Global(BUILTIN_GLOBAL_VARS_SYMBOL.into()));
                    }
                    if self.has_global(selector)? {
                        if let Some(lookup) = self.lookup {
                            let query = dm_ir::ResolveQuery::VarStorage {
                                owner: dm_ir::SymbolId::of("/"),
                                name: dm_ir::SymbolId::of(selector),
                            };
                            let slot = self.semantic(lookup.slot(query))?.ok_or_else(|| {
                                error(statement, "global variable has no shared storage")
                            })?;
                            return Ok(VariableWord::Global(slot));
                        }
                        return Ok(VariableWord::Global(selector.clone()));
                    }
                    return Err(error(
                        statement,
                        &format!("unresolved global variable: {selector}"),
                    ));
                }
                if let Some(owner) = if *via_colon {
                    None
                } else {
                    self.inferred_expression_type(object)?
                } {
                    if let Some(symbol) = self.member_global(&owner, selector)? {
                        return Ok(VariableWord::Global(symbol.to_owned()));
                    }
                }
                let owner = self.variable_expr(object, statement)?;
                self.intern_string(selector);
                Ok(VariableWord::SetCache(
                    Box::new(owner),
                    Box::new(VariableWord::Field(selector.clone())),
                ))
            }
            _ => Err(error(statement, "unsupported variable target")),
        }
    }

    fn assignment_value_preserving_cache(
        &mut self,
        variable: &VariableWord,
        value: &Expr,
        statement: &str,
    ) -> Result<(), LowerError> {
        let clobbers = !matches!(&value.kind, ExprKind::Ident(_) | ExprKind::TypePath(_))
            && !matches!(&value.kind, ExprKind::Literal(text) if !text.contains('['));
        let receiver =
            clobbers && matches!(variable, VariableWord::CacheIndex | VariableWord::Field(_));
        let index = clobbers && matches!(variable, VariableWord::CacheIndex);
        if receiver {
            self.emit(opcode::PUSH_CACHE, vec![]);
        }
        if index {
            self.emit(opcode::PUSH_CACHE_KEY, vec![]);
        }
        self.expression(value, statement)?;
        if index {
            self.emit(opcode::POP_CACHE_KEY, vec![]);
        }
        if receiver {
            self.emit(opcode::POP_CACHE, vec![]);
        }
        Ok(())
    }

    fn assignment_variable(
        &mut self,
        target: &Expr,
        statement: &str,
    ) -> Result<VariableWord, LowerError> {
        if let ExprKind::Index { object, index } = &target.kind {
            self.expression(object, statement)?;
            self.expression(index, statement)?;
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::CacheKey)],
            );
            self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
            return Ok(VariableWord::CacheIndex);
        }
        match self.variable_expr(target, statement) {
            Ok(variable) => {
                self.ensure_writable(&variable, statement)?;
                Ok(variable)
            }
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "unsupported assignment target"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                if let Some(symbol) = self.fallback_member_global(
                    object,
                    selector,
                    matches!(
                        &target.kind,
                        ExprKind::Member {
                            via_colon: true,
                            ..
                        }
                    ),
                )? {
                    return Ok(VariableWord::Global(symbol.to_owned()));
                }
                self.intern_string(selector);
                Ok(VariableWord::Field(selector.clone()))
            }
        }
    }

    fn modified_fields(&mut self, fields: &[(String, Expr)]) -> Result<(), LowerError> {
        let owner = self
            .bindings
            .current_type_path
            .clone()
            .ok_or_else(|| error("modified initializer", "receiver type is missing"))?;
        for (index, (name, value)) in fields.iter().enumerate() {
            self.statement_span = Some(LowerSpan {
                start: value.span.start,
                end: value.span.end,
            });
            if let Some(debug) = self.debug {
                self.debug_current = Some(
                    debug
                        .ordinal(index)
                        .map_err(|reason| error("modified initializer", &reason))?,
                );
            }
            let lookup = self
                .lookup
                .ok_or_else(|| error("modified initializer", "immutable resolver is missing"))?;
            if !self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                owner: dm_ir::SymbolId::of(&owner),
                name: dm_ir::SymbolId::of(name),
            }))? {
                return Err(error("modified initializer", "modified field is absent"));
            }
            self.expression(value, "modified initializer")?;
            self.intern_string(name);
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::SetCache(
                    Box::new(VariableWord::Src),
                    Box::new(VariableWord::Field(name.clone())),
                ))],
            );
        }
        Ok(())
    }
    fn inc_dec(&mut self, target: &Expr, opcode: u32, statement: &str) -> Result<(), LowerError> {
        if let ExprKind::Call { callee, args } = &target.kind {
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "length") {
                let [list] = args.as_slice() else {
                    return Err(error(
                        statement,
                        "length increment requires one list variable",
                    ));
                };
                let variable = self.variable_expr(list, statement)?;
                self.emit(opcode, vec![Word::Variable(variable)]);
                return Ok(());
            }
        }
        if let ExprKind::Index { object, index } = &target.kind {
            self.expression(object, statement)?;
            self.expression(index, statement)?;
            self.emit(
                opcode::SET_VAR,
                vec![Word::Variable(VariableWord::CacheKey)],
            );
            self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
            self.emit(opcode, vec![Word::Variable(VariableWord::CacheIndex)]);
            return Ok(());
        }
        let variable = match self.variable_expr(target, statement) {
            Ok(variable) => variable,
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "increment target must be a variable"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.intern_string(selector);
                VariableWord::Field(selector.clone())
            }
        };
        self.ensure_writable(&variable, statement)?;
        self.emit(opcode, vec![Word::Variable(variable)]);
        Ok(())
    }

    fn ensure_writable(&self, variable: &VariableWord, statement: &str) -> Result<(), LowerError> {
        if matches!(variable, VariableWord::Arg(slot) if self.bindings.readonly_parameters.contains(slot))
        {
            let mut failure = error(statement, "cannot change constant parameter binding");
            failure.kind = LowerErrorKind::SourceError;
            // Keep this semantic failure sticky across legacy syntax fallbacks.
            return self.semantic(Err(failure));
        }
        Ok(())
    }

    /// Mirrors contextual cases consumed by local_initializer. Nested call
    /// arguments/conditions use ordinary expression lowering, not target type.
    fn assignment_needs_target_type(expr: &Expr) -> bool {
        match &expr.kind {
            ExprKind::Ident(name) => name == "new",
            ExprKind::Call { callee, args } => matches!(&callee.kind, ExprKind::Ident(name)
                if name == "new" || (name == "locate" && args.is_empty())),
            ExprKind::Group(inner) => Self::assignment_needs_target_type(inner),
            ExprKind::Binary { op, lhs, rhs } if op == "||" || op == "&&" => {
                Self::assignment_needs_target_type(lhs) || Self::assignment_needs_target_type(rhs)
            }
            ExprKind::Binary { op, lhs, .. } if op == "in" => {
                matches!(&lhs.kind, ExprKind::Call { callee, args }
                    if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "locate"))
            }
            ExprKind::Conditional {
                then_value,
                else_value,
                ..
            } => {
                Self::assignment_needs_target_type(then_value)
                    || Self::assignment_needs_target_type(else_value)
            }
            _ => false,
        }
    }
    fn local_initializer(
        &mut self,
        expr: &Expr,
        declaration: &str,
        statement: &str,
    ) -> Result<(), LowerError> {
        if let ExprKind::Group(inner) = &expr.kind {
            return self.local_initializer(inner, declaration, statement);
        }
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if op == "||" || op == "&&" {
                self.local_initializer(lhs, declaration, statement)?;
                let end = self.label();
                self.emit(
                    if op == "||" {
                        opcode::JMP_OR
                    } else {
                        opcode::JMP_AND
                    },
                    vec![Word::Branch(end.clone())],
                );
                self.local_initializer(rhs, declaration, statement)?;
                self.result.code.items.push(CodeItem::Label(end));
                return Ok(());
            }
        }
        if matches!(&expr.kind, ExprKind::Call { callee, args }
            if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "locate"))
        {
            let type_name = declaration
                .strip_prefix("var/")
                .and_then(|raw| raw.rsplit_once('/'))
                .map(|(path, _)| path)
                .filter(|path| !path.is_empty())
                .ok_or_else(|| error(statement, "locate() requires a typed assignment"))?;
            let path = runtime_declaration_path(type_name);
            let tag = self
                .class_tag(&path)?
                .ok_or_else(|| error(statement, "unsupported inferred locate type"))?;
            if self.seen_classes.insert(path.clone()) {
                self.result.class_paths.push(path.clone());
            }
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::ClassPath { path, tag })],
            );
            self.emit(0x5b, vec![]);
            return Ok(());
        }
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if op == "in"
                && matches!(&lhs.kind, ExprKind::Call { callee, args }
                    if args.is_empty() && matches!(&callee.kind, ExprKind::Ident(name) if name == "locate"))
            {
                let type_name = declaration
                    .strip_prefix("var/")
                    .and_then(|raw| raw.rsplit_once('/'))
                    .map(|(path, _)| path)
                    .filter(|path| !path.is_empty())
                    .ok_or_else(|| error(statement, "locate() requires a typed assignment"))?;
                let path = runtime_declaration_path(type_name);
                let tag = self
                    .class_tag(&path)?
                    .ok_or_else(|| error(statement, "unsupported inferred locate type"))?;
                if self.seen_classes.insert(path.clone()) {
                    self.result.class_paths.push(path.clone());
                }
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::ClassPath { path, tag })],
                );
                self.expression(rhs, statement)?;
                self.emit(0x97, vec![]);
                return Ok(());
            }
        }
        if let ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } = &expr.kind
        {
            self.expression(condition, statement)?;
            self.emit(opcode::TEST, vec![]);
            let else_label = self.label();
            let end_label = self.label();
            self.emit(opcode::JZ, vec![Word::Branch(else_label.clone())]);
            self.local_initializer(then_value, declaration, statement)?;
            self.emit(opcode::JMP, vec![Word::Branch(end_label.clone())]);
            self.result.code.items.push(CodeItem::Label(else_label));
            if matches!(&else_value.kind, ExprKind::Literal(value) if value == "null") {
                self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Null)]);
            } else {
                self.local_initializer(else_value, declaration, statement)?;
            }
            self.result.code.items.push(CodeItem::Label(end_label));
            return Ok(());
        }
        let inferred_new_args: Option<&[Expr]> = match &expr.kind {
            ExprKind::Ident(name) if name == "new" => Some(&[]),
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "new") => {
                Some(args)
            }
            _ => None,
        };
        if let Some(args) = inferred_new_args {
            let type_name = declaration
                .strip_prefix("var/")
                .and_then(|raw| raw.rsplit_once('/'))
                .map(|(path, _)| path)
                .filter(|path| !path.is_empty())
                .or_else(|| declaration.trim_end().ends_with("[]").then_some("list"))
                .ok_or_else(|| error(statement, "inferred new requires a typed local"))?;
            let path = runtime_declaration_path(type_name);
            let tag = self
                .class_tag(&path)?
                .ok_or_else(|| error(statement, "unsupported inferred constructor type"))?;
            if self.seen_classes.insert(path.clone()) {
                self.result.class_paths.push(path.clone());
            }
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::ClassPath { path, tag })],
            );
            if args
                .iter()
                .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="))
            {
                self.named_arguments(args, statement)?;
                self.emit(0xcf, vec![]);
            } else if let [Expr {
                kind:
                    ExprKind::Call {
                        callee,
                        args: list_args,
                    },
                ..
            }] = args
            {
                if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist")
                    && list_args.len() == 1
                {
                    self.expression(&list_args[0], statement)?;
                    self.emit(0xcf, vec![]);
                } else {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
                }
            } else {
                for arg in args {
                    self.expression(arg, statement)?;
                }
                self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
            }
            return Ok(());
        }
        self.expression(expr, statement)
    }

    fn inferred_expression_type(&self, expr: &Expr) -> Result<Option<String>, LowerError> {
        let inferred = match &expr.kind {
            ExprKind::TypePath(path) => Some(path.clone()),
            ExprKind::Ident(name) => {
                if name == "src" {
                    return match self.bindings.current_type_path.as_deref() {
                        Some(path) => self.normalize_inferred_type(path).map(Some),
                        None => Ok(None),
                    };
                }
                if name == "usr" {
                    return self.normalize_inferred_type("/mob").map(Some);
                }
                // Match variable() binding precedence. A nearer lexical binding
                // with no declared type is proven untyped, not an outer lookup.
                if self.local_slots.contains_key(name) {
                    return self
                        .local_types
                        .get(name)
                        .map(|path| self.normalize_inferred_type(&runtime_declaration_path(path)))
                        .transpose();
                }
                if self
                    .bindings
                    .parameters
                    .iter()
                    .any(|parameter| parameter == name)
                {
                    return self
                        .bindings
                        .parameter_types
                        .get(name)
                        .map(|path| self.normalize_inferred_type(&runtime_declaration_path(path)))
                        .transpose();
                }
                {
                    if let Some(lookup) = self.lookup {
                        if let Some(declaration) = self.semantic(
                            lookup.procedure_static(self.bindings.procedure_identity, name),
                        )? {
                            return declaration
                                .declared_type
                                .map(|id| {
                                    self.semantic(lookup.text(
                                        dm_ir::ResolveQuery::ProcedureStatic {
                                            procedure: declaration.identity.procedure,
                                            name: declaration.identity.name,
                                        },
                                        id,
                                    ))
                                })
                                .transpose();
                        }
                    }
                    if name == "world" {
                        return self.normalize_inferred_type("/world").map(Some);
                    }
                    if name == "args" {
                        return self.normalize_inferred_type("/list").map(Some);
                    }
                    if matches!(name.as_str(), "caller" | "callee") {
                        return self.normalize_inferred_type("/callee").map(Some);
                    }
                    if name == "." {
                        // The return-value register has no declared receiver
                        // type. It is not an outer member/global identifier.
                        return Ok(None);
                    }
                    if let (Some(lookup), Some(owner)) =
                        (self.lookup, self.bindings.current_type_path.as_deref())
                    {
                        if self.semantic(lookup.presence(dm_ir::ResolveQuery::HasMemberVar {
                            owner: dm_ir::SymbolId::of(owner),
                            name: dm_ir::SymbolId::of(name),
                        }))? {
                            // Proven untyped is an answer, not permission to look
                            // through the nearer field into the global namespace.
                            return self
                                .field_type(name)?
                                .map(|path| self.normalize_inferred_type(&path))
                                .transpose();
                        }
                        return self
                            .global_type(name)?
                            .map(|path| self.normalize_inferred_type(&path))
                            .transpose();
                    }
                    match self.field_type(name)? {
                        Some(path) => Some(path),
                        None => self.global_type(name)?,
                    }
                }
            }
            ExprKind::Group(inner) => self.inferred_expression_type(inner)?,
            ExprKind::Member {
                object,
                selector,
                via_colon,
            } => {
                // A colon selector intentionally carries no static receiver
                // field contract, even when its receiver has an authored type.
                if *via_colon {
                    return Ok(None);
                }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                    return self
                        .global_type(selector)?
                        .map(|path| self.normalize_inferred_type(&path))
                        .transpose();
                }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "src") {
                    return self
                        .field_type(selector)?
                        .map(|path| self.normalize_inferred_type(&path))
                        .transpose();
                }
                match self.inferred_expression_type(object)? {
                    Some(owner) => self.member_type(&owner, selector)?,
                    None => None,
                }
            }
            ExprKind::SafeMember { object, selector } => {
                match self.inferred_expression_type(object)? {
                    Some(owner) => self.member_type(&owner, selector)?,
                    None => None,
                }
            }
            ExprKind::Call { callee, .. } if self.lookup.is_some() => {
                let lookup = self.lookup.unwrap();
                match &callee.kind {
                    ExprKind::Ident(name) => {
                        if crate::builtin_catalog::lookup(name).is_some() {
                            return Ok(None);
                        }
                        if let Some(owner) = self.bindings.current_type_path.as_deref() {
                            if self.has_declared_member_proc(owner, name)? {
                                return self.semantic(lookup.procedure_return_type(
                                    dm_ir::ResolveQuery::Proc {
                                        owner: dm_ir::SymbolId::of(owner),
                                        name: dm_ir::SymbolId::of(name),
                                        verb: false,
                                    },
                                ));
                            }
                        }
                        self.semantic(lookup.procedure_return_type(
                            dm_ir::ResolveQuery::GlobalProc(dm_ir::SymbolId::of(name)),
                        ))?
                    }
                    ExprKind::Member {
                        object,
                        selector,
                        via_colon: false,
                    }
                    | ExprKind::SafeMember { object, selector } => {
                        match self.inferred_expression_type(object)? {
                            Some(owner) => self.semantic(lookup.procedure_return_type(
                                dm_ir::ResolveQuery::Proc {
                                    owner: dm_ir::SymbolId::of(&owner),
                                    name: dm_ir::SymbolId::of(selector),
                                    verb: false,
                                },
                            ))?,
                            None => None,
                        }
                    }
                    _ => None,
                }
            }
            _ => None,
        };
        let Some(path) = inferred else {
            return Ok(None);
        };
        self.normalize_inferred_type(&path).map(Some)
    }
    fn normalize_inferred_type(&self, path: &str) -> Result<String, LowerError> {
        if let Some(lookup) = self.lookup {
            return self.semantic(lookup.runtime_type(path));
        }
        Ok(self
            .bindings
            .shared
            .as_ref()
            .and_then(|shared| shared.modified_instances.get(path))
            .cloned()
            .unwrap_or_else(|| path.to_owned()))
    }
    fn expression_member_global(
        &self,
        object: &Expr,
        name: &str,
    ) -> Result<Option<String>, LowerError> {
        match self.inferred_expression_type(object)? {
            Some(owner) => self.member_global(&owner, name),
            None => Ok(None),
        }
    }
    fn expression_member_proc(
        &self,
        object: &Expr,
        name: &str,
    ) -> Result<Option<String>, LowerError> {
        match self.inferred_expression_type(object)? {
            Some(owner) => self.member_proc(&owner, name),
            None => Ok(None),
        }
    }
    fn current_member_proc(&self, name: &str) -> Result<Option<String>, LowerError> {
        match self.bindings.current_type_path.as_deref() {
            Some(owner) => self.member_proc(owner, name),
            None => Ok(None),
        }
    }
    fn current_has_declared_member_proc(&self, name: &str) -> Result<bool, LowerError> {
        match self.bindings.current_type_path.as_deref() {
            Some(owner) => self.has_declared_member_proc(owner, name),
            None => Ok(false),
        }
    }
    fn local_array(&mut self, dimensions: &[&str], statement: &str) -> Result<(), LowerError> {
        if dimensions.len() > 1 {
            let path = "/list".to_owned();
            if self.seen_classes.insert(path.clone()) {
                self.result.class_paths.push(path.clone());
            }
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::ClassPath { path, tag: 40 })],
            );
        }
        for size in dimensions {
            self.expression_text(size, statement)?;
        }
        self.emit(
            if dimensions.len() == 1 {
                opcode::EMPTY_LIST
            } else {
                opcode::NEW
            },
            if dimensions.len() == 1 {
                vec![]
            } else {
                vec![Word::Immediate(dimensions.len() as u32)]
            },
        );
        Ok(())
    }

    fn named_arguments(&mut self, args: &[Expr], statement: &str) -> Result<(), LowerError> {
        for (index, arg) in args.iter().enumerate() {
            if let ExprKind::Binary { op, lhs, rhs } = &arg.kind {
                if op == "=" {
                    if let ExprKind::Ident(name) = &lhs.kind {
                        self.intern_string(name);
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::String(name.clone()))],
                        );
                    } else {
                        self.expression(lhs, statement)?;
                    }
                    if matches!(&rhs.kind, ExprKind::Literal(value) if value == "null") {
                        self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Null)]);
                    } else {
                        self.expression(rhs, statement)?;
                    }
                    continue;
                }
            }
            self.emit(opcode::PUSH_INT, vec![Word::Immediate(index as u32 + 1)]);
            self.expression(arg, statement)?;
        }
        self.emit(0xc8, vec![Word::Immediate(args.len() as u32)]);
        Ok(())
    }

    fn input_call(
        &mut self,
        args: &[Expr],
        types: &[String],
        choices: Option<&Expr>,
        statement: &str,
    ) -> Result<(), LowerError> {
        if args.len() > 4 {
            return Err(error(
                statement,
                "input() accepts at most four prompt arguments",
            ));
        }
        let mut mask = 0u32;
        let mut special = 0u32;
        for ty in types {
            mask |= match ty.as_str() {
                "mob" => 1,
                "obj" => 2,
                "text" => 4,
                "num" => 8,
                "file" => 16,
                "turf" => 32,
                "null" => 128,
                "area" => 256,
                "icon" => 512,
                "sound" => 1024,
                "message" => 2048,
                "anything" => 4096,
                "password" => 32768,
                "color" => {
                    special |= 131072;
                    0
                }
                _ => return Err(error(statement, "unsupported input type")),
            };
        }
        if special != 0 {
            self.emit(
                opcode::PUSH_VAL,
                vec![Word::Value(ValueWord::Number(
                    ((special | mask) as f32).to_bits(),
                ))],
            );
        }
        if let Some(choices) = choices {
            self.expression(choices, statement)?;
        }
        for arg in args {
            if matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "=") {
                return Err(error(statement, "named input arguments are not lowered"));
            }
            self.expression(arg, statement)?;
        }
        for _ in args.len()..4 {
            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
        }
        self.emit(
            if special != 0 { 0xc6 } else { 0xc1 },
            vec![
                Word::Immediate(if special != 0 { 0 } else { mask }),
                Word::Immediate(0),
                Word::Immediate(if choices.is_some() { 64 } else { 0 }),
            ],
        );
        self.emit(0xba, vec![]);
        Ok(())
    }

    fn input_form<'b>(&self, expr: &'b Expr) -> Option<(&'b [Expr], &'b [String])> {
        match &expr.kind {
            ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "input") => {
                Some((args, &[]))
            }
            ExprKind::TypeFilter { value, types } => {
                let ExprKind::Call { callee, args } = &value.kind else {
                    return None;
                };
                matches!(&callee.kind, ExprKind::Ident(name) if name == "input")
                    .then_some((args, types))
            }
            _ => None,
        }
    }

    fn condition(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        if let ExprKind::Binary { op, lhs, rhs } = &expr.kind {
            if op == "==" {
                self.expression(lhs, statement)?;
                self.expression(rhs, statement)?;
                self.emit(opcode::TEQ, vec![]);
                self.emit(opcode::POP, vec![]);
                return Ok(());
            }
        }
        self.expression(expr, statement)?;
        self.emit(opcode::TEST, vec![]);
        Ok(())
    }

    fn defer_safe_postfix_labels(&mut self, expr: &Expr) -> Vec<CodeItem> {
        fn is_safe_chain(expr: &Expr) -> bool {
            match &expr.kind {
                ExprKind::SafeMember { .. } | ExprKind::SafeIndex { .. } => true,
                ExprKind::Member { object, .. }
                | ExprKind::StaticMember { object, .. }
                | ExprKind::Index { object, .. } => is_safe_chain(object),
                ExprKind::Call { callee, .. } => is_safe_chain(callee),
                _ => false,
            }
        }
        let mut labels = Vec::new();
        if is_safe_chain(expr) {
            while matches!(self.result.code.items.last(), Some(CodeItem::Label(_))) {
                labels.push(self.result.code.items.pop().unwrap());
            }
            labels.reverse();
        }
        labels
    }

    fn expression(&mut self, expr: &Expr, statement: &str) -> Result<(), LowerError> {
        if let Some(number) = fold_number(expr) {
            if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
            } else {
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::Number(number.to_bits()))],
                );
            }
            return Ok(());
        }
        match &expr.kind {
            ExprKind::ObjectInitializer { object, fields } => {
                let ExprKind::TypePath(path) = &object.kind else {
                    return Err(error(
                        statement,
                        "modified instance requires an explicit type",
                    ));
                };
                let lookup = self.lookup.ok_or_else(|| {
                    error(
                        statement,
                        "object initializer requires captured descriptor support",
                    )
                })?;
                let owner = self.bindings.current_type_path.as_deref().unwrap_or("/");
                let alias = self.semantic(lookup.modified_instance(
                    path.trim_end_matches('/'),
                    owner,
                    fields,
                    self.debug_current,
                ))?;
                if !self.result.instance_paths.contains(&alias) {
                    self.result.instance_paths.push(alias.clone());
                }
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::Instance(alias))],
                );
            }
            ExprKind::TypeFilter { .. } => {
                if let Some((args, types)) = self.input_form(expr) {
                    self.input_call(args, types, None, statement)?;
                } else if let ExprKind::TypeFilter { value, .. } = &expr.kind {
                    self.expression(value, statement)?;
                }
            }
            ExprKind::Binary { op, lhs, rhs } if op == "in" => {
                if let ExprKind::Call { callee, args } = &lhs.kind {
                    if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate")
                        && args.len() == 1
                    {
                        self.expression(&args[0], statement)?;
                        self.expression(rhs, statement)?;
                        self.emit(0x97, vec![]);
                        return Ok(());
                    }
                }
                if let Some((args, types)) = self.input_form(lhs) {
                    self.input_call(args, types, Some(rhs), statement)?;
                } else if let ExprKind::Binary {
                    op: range_op,
                    lhs: low,
                    rhs: high,
                } = &rhs.kind
                {
                    if range_op == "to" {
                        self.expression(low, statement)?;
                        self.expression(high, statement)?;
                        self.expression(lhs, statement)?;
                        self.emit(0xa9, vec![Word::Immediate(11)]);
                        self.emit(0x36, vec![]);
                    } else {
                        self.expression(rhs, statement)?;
                        self.expression(lhs, statement)?;
                        self.emit(0xa9, vec![Word::Immediate(5)]);
                        self.emit(0x36, vec![]);
                    }
                } else {
                    self.expression(rhs, statement)?;
                    self.expression(lhs, statement)?;
                    self.emit(0xa9, vec![Word::Immediate(5)]);
                    self.emit(0x36, vec![]);
                }
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                self.condition(condition, statement)?;
                let else_label = self.label();
                let end_label = self.label();
                self.emit(opcode::JZ, vec![Word::Branch(else_label.clone())]);
                self.expression(then_value, statement)?;
                self.emit(opcode::JMP, vec![Word::Branch(end_label.clone())]);
                self.result.code.items.push(CodeItem::Label(else_label));
                self.expression(else_value, statement)?;
                self.result.code.items.push(CodeItem::Label(end_label));
            }
            ExprKind::Literal(literal) => {
                if literal == "null" {
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                } else if literal == "FALSE" {
                    self.emit(opcode::PUSH_INT, vec![Word::Immediate(0)]);
                } else if literal == "TRUE" {
                    self.emit(opcode::PUSH_INT, vec![Word::Immediate(1)]);
                } else if literal.starts_with("@{\"")
                    && literal.ends_with("\"}")
                    && literal.len() >= 5
                {
                    let value = literal[3..literal.len() - 2].to_owned();
                    self.intern_string(&value);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(value))],
                    );
                } else if literal.starts_with("@\"") && literal.ends_with('"') && literal.len() >= 3
                {
                    let value = literal[2..literal.len() - 1].to_owned();
                    self.intern_string(&value);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(value))],
                    );
                } else if (literal.starts_with('"') && literal.ends_with('"') && literal.len() >= 2)
                    || (literal.starts_with("{\"")
                        && literal.ends_with("\"}")
                        && literal.len() >= 4)
                {
                    let value = if literal.starts_with("{\"") {
                        &literal[2..literal.len() - 2]
                    } else {
                        &literal[1..literal.len() - 1]
                    };
                    let (template, expressions) = parse_interpolated_string(value)
                        .map_err(|reason| error(statement, &reason))?;
                    if expressions.is_empty() {
                        let value = match String::from_utf8(template.clone()) {
                            Ok(value) => {
                                self.intern_string(&value);
                                value
                            }
                            Err(_) => self.intern_format_template(template),
                        };
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::String(value))],
                        );
                    } else {
                        for expression in &expressions {
                            self.expression(expression, statement)?;
                        }
                        let key = self.intern_format_template(template);
                        self.emit(
                            2,
                            vec![
                                Word::Reference(crate::Symbol::new(crate::Table::String, key)),
                                Word::Immediate(expressions.len() as u32),
                            ],
                        );
                    }
                } else if literal.starts_with("@'") && literal.ends_with('\'') && literal.len() >= 3
                {
                    let value = literal[2..literal.len() - 1].to_owned();
                    self.intern_string(&value);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(value))],
                    );
                } else if literal.starts_with('\'') && literal.ends_with('\'') && literal.len() >= 2
                {
                    let path = &literal[1..literal.len() - 1];
                    if path.contains(['\\', '[', ']']) {
                        return Err(error(
                            statement,
                            "escaped or interpolated resource path is unsupported",
                        ));
                    }
                    let path = match self.lookup {
                        Some(lookup) => self.semantic(lookup.resource(path))?,
                        None => path.to_owned(),
                    };
                    if self.seen_resources.insert(path.clone()) {
                        self.result.resources.push(path.clone());
                    }
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::Resource(path))],
                    );
                } else if let Ok(number) = literal.parse::<f32>() {
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::Number(number.to_bits()))],
                    );
                } else {
                    return Err(error(statement, "unsupported literal"));
                }
            }
            ExprKind::TypePath(path) => {
                if path.ends_with("/proc") || path.ends_with("/verb") {
                    // A procedure namespace is a native string path used by
                    // typesof(), not a runtime class or a single procedure.
                    self.intern_string(path);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(path.clone()))],
                    );
                    return Ok(());
                }
                if path.starts_with("/proc/")
                    || path.contains("/proc/")
                    || path.starts_with("/verb/")
                    || path.contains("/verb/")
                {
                    let value_path = match self.lookup {
                        Some(lookup) => self.semantic(lookup.procedure_literal(path))?,
                        None => path.clone(),
                    };
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ProcPath(value_path))],
                    );
                    return Ok(());
                }
                let tag = self
                    .class_tag(path)?
                    .ok_or_else(|| error(statement, "unsupported type path literal"))?;
                if self.seen_classes.insert(path.clone()) {
                    self.result.class_paths.push(path.clone());
                }
                self.emit(
                    opcode::PUSH_VAL,
                    vec![Word::Value(ValueWord::ClassPath {
                        path: path.clone(),
                        tag,
                    })],
                );
            }
            ExprKind::Ident(name) => {
                if name == "__PROC__"
                    && !self.local_slots.contains_key(name)
                    && !self
                        .bindings
                        .parameters
                        .iter()
                        .any(|parameter| parameter == name)
                {
                    if let Some(lookup) = self.lookup {
                        if self
                            .semantic(
                                lookup
                                    .procedure_static_slot(self.bindings.procedure_identity, name),
                            )?
                            .is_some()
                        {
                            let variable = self.variable(name, statement)?;
                            self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                            return Ok(());
                        }
                    }
                    let path = if let Some(lookup) = self.lookup {
                        let identity = self.bindings.procedure_identity.ok_or_else(|| {
                            error(
                                statement,
                                "__PROC__ requires exact current procedure identity",
                            )
                        })?;
                        self.semantic(lookup.procedure_value_key(identity))?
                    } else {
                        self.bindings.current_proc_path.clone().ok_or_else(|| {
                            error(statement, "__PROC__ requires current procedure context")
                        })?
                    };
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ProcPath(path))],
                    );
                    return Ok(());
                }
                if name == "null" || name == "FALSE" || name == "TRUE" {
                    let literal = Expr {
                        kind: ExprKind::Literal(name.clone()),
                        span: expr.span,
                    };
                    return self.expression(&literal, statement);
                }
                if !matches!(
                    name.as_str(),
                    "src" | "usr" | "world" | "args" | "caller" | "callee" | "."
                ) && !self.local_slots.contains_key(name)
                    && !self
                        .bindings
                        .parameters
                        .iter()
                        .any(|parameter| parameter == name)
                    && !self.has_field(name)?
                    && !self.has_visible_global(name)?
                {
                    if name == "__PROC__" {
                        let path = self
                            .bindings
                            .current_proc_path
                            .as_ref()
                            .ok_or_else(|| {
                                error(statement, "__PROC__ requires current procedure context")
                            })?
                            .clone();
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::ProcPath(path))],
                        );
                        return Ok(());
                    }
                    if name == "__TYPE__" {
                        if let Some(path) = self.bindings.current_type_path.as_ref() {
                            let path = path.clone();
                            let tag = self.class_tag(&path)?.ok_or_else(|| {
                                error(statement, "__TYPE__ has unsupported owner type")
                            })?;
                            if self.seen_classes.insert(path.clone()) {
                                self.result.class_paths.push(path.clone());
                            }
                            self.emit(
                                opcode::PUSH_VAL,
                                vec![Word::Value(ValueWord::ClassPath { path, tag })],
                            );
                        } else {
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                        }
                        return Ok(());
                    }
                    if let Some(bits) = self.numeric_constant(name)? {
                        let number = f32::from_bits(bits);
                        if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                            self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
                        } else {
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Number(bits))]);
                        }
                        return Ok(());
                    }
                    if let Some(value) = self.string_constant(name)? {
                        self.intern_string(&value);
                        self.emit(
                            opcode::PUSH_VAL,
                            vec![Word::Value(ValueWord::String(value))],
                        );
                        return Ok(());
                    }
                }
                let var = self.variable(name, statement)?;
                self.emit(opcode::GET_VAR, vec![Word::Variable(var)]);
            }
            ExprKind::Member { .. } => {
                let mut safe_labels = Vec::new();
                let var = match self.variable_expr(expr, statement) {
                    Ok(var) => var,
                    Err(_) => {
                        let ExprKind::Member {
                            object, selector, ..
                        } = &expr.kind
                        else {
                            return Err(error(statement, "unsupported member expression"));
                        };
                        self.expression(object, statement)?;
                        safe_labels = self.defer_safe_postfix_labels(object);
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        if let Some(symbol) = self.fallback_member_global(
                            object,
                            selector,
                            matches!(
                                &expr.kind,
                                ExprKind::Member {
                                    via_colon: true,
                                    ..
                                }
                            ),
                        )? {
                            VariableWord::Global(symbol.to_owned())
                        } else {
                            self.intern_string(selector);
                            VariableWord::Field(selector.clone())
                        }
                    }
                };
                self.emit(opcode::GET_VAR, vec![Word::Variable(var)]);
                self.result.code.items.extend(safe_labels);
            }
            ExprKind::StaticMember { object, selector } => {
                self.expression(object, statement)?;
                let safe_labels = self.defer_safe_postfix_labels(object);
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.intern_string(selector);
                self.emit(
                    opcode::GET_VAR,
                    vec![Word::Variable(VariableWord::StaticField(selector.clone()))],
                );
                self.result.code.items.extend(safe_labels);
            }
            ExprKind::SafeMember { object, selector } => {
                self.expression(object, statement)?;
                let end = self.label();
                self.emit(317, vec![Word::Branch(end.clone())]);
                let variable = self
                    .expression_member_global(object, selector)?
                    .map(|symbol| VariableWord::Global(symbol.to_owned()))
                    .unwrap_or_else(|| VariableWord::Field(selector.clone()));
                if matches!(variable, VariableWord::Field(_)) {
                    self.intern_string(selector);
                }
                self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                self.result.code.items.push(CodeItem::Label(end));
            }
            ExprKind::Index { object, index } => {
                self.expression(object, statement)?;
                let safe_labels = self.defer_safe_postfix_labels(object);
                self.expression(index, statement)?;
                self.emit(opcode::LIST_GET, vec![]);
                self.result.code.items.extend(safe_labels);
            }
            ExprKind::SafeIndex { object, index } => {
                self.expression(object, statement)?;
                let end = self.label();
                self.emit(317, vec![Word::Branch(end.clone())]);
                self.emit(opcode::PUSH_CACHE, vec![]);
                self.emit(opcode::GET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                self.expression(index, statement)?;
                self.emit(opcode::LIST_GET, vec![]);
                self.emit(opcode::POP_CACHE, vec![]);
                self.result.code.items.push(CodeItem::Label(end));
            }
            ExprKind::Group(inner) => self.expression(inner, statement)?,
            ExprKind::Unary { op, value } => {
                if matches!(op.as_str(), "post++" | "post--" | "pre++" | "pre--") {
                    let opcode = match op.as_str() {
                        "pre++" => 0x62,
                        "post++" => 0x63,
                        "pre--" => 0x64,
                        "post--" => 0x65,
                        _ => unreachable!(),
                    };
                    return self.inc_dec(value, opcode, statement);
                }
                if op == "new" {
                    if let ExprKind::Call {
                        callee,
                        args: method_args,
                    } = &value.kind
                    {
                        if let ExprKind::Member {
                            object, selector, ..
                        } = &callee.kind
                        {
                            if matches!(&object.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::TypePath(_)))
                            {
                                let constructor = Expr {
                                    kind: ExprKind::Unary {
                                        op: "new".into(),
                                        value: object.clone(),
                                    },
                                    span: expr.span,
                                };
                                self.expression(&constructor, statement)?;
                                self.emit(
                                    opcode::SET_VAR,
                                    vec![Word::Variable(VariableWord::Cache)],
                                );
                                self.emit(opcode::PUSH_CACHE, vec![]);
                                let named = method_args.iter().any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
                                if named {
                                    self.named_arguments(method_args, statement)?;
                                } else {
                                    for arg in method_args {
                                        self.expression(arg, statement)?;
                                    }
                                }
                                self.emit(opcode::POP_CACHE, vec![]);
                                let proc_selector =
                                    if let ExprKind::Call { callee, .. } = &object.kind {
                                        if let ExprKind::TypePath(path) = &callee.kind {
                                            self.member_proc(path, selector)?
                                        } else {
                                            None
                                        }
                                    } else {
                                        None
                                    };
                                let proc_selector =
                                    proc_selector.map(member_proc_selector).unwrap_or_else(|| {
                                        VariableWord::DynamicProc(selector.replace('_', " "))
                                    });
                                if let VariableWord::DynamicProc(display) = &proc_selector {
                                    self.intern_string(display);
                                }
                                self.emit(
                                    opcode::CALL,
                                    vec![
                                        Word::Variable(proc_selector),
                                        Word::Immediate(if named {
                                            u16::MAX as u32
                                        } else {
                                            method_args.len() as u32
                                        }),
                                    ],
                                );
                                return Ok(());
                            }
                        }
                    }
                    let (target, args): (&Expr, &[Expr]) = match &value.kind {
                        ExprKind::Call { callee, args } => (callee, args),
                        _ => (value, &[]),
                    };
                    // Native new accepts class values and proc/verb references.
                    // Use the same symbolic path encoding as ordinary values.
                    self.expression(target, statement)?;
                    if args
                        .iter()
                        .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="))
                    {
                        self.named_arguments(args, statement)?;
                        self.emit(0xcf, vec![]);
                    } else if let [Expr {
                        kind:
                            ExprKind::Call {
                                callee,
                                args: list_args,
                            },
                        ..
                    }] = args
                    {
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                            let [list] = list_args.as_slice() else {
                                return Err(error(statement, "arglist() requires one argument"));
                            };
                            self.expression(list, statement)?;
                            self.emit(0xcf, vec![]);
                        } else {
                            self.expression(&args[0], statement)?;
                            self.emit(opcode::NEW, vec![Word::Immediate(1)]);
                        }
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
                    }
                    return Ok(());
                }
                self.expression(value, statement)?;
                let opcode = match op.as_str() {
                    "-" => opcode::UNARY_NEG,
                    "!" => opcode::NOT,
                    "~" => opcode::BNOT,
                    "+" => return Ok(()),
                    _ => return Err(error(statement, "unsupported unary operator")),
                };
                self.emit(opcode, vec![]);
            }
            ExprKind::Binary { op, lhs, rhs } if op == "=" => {
                if let ExprKind::Index { object, index } = &lhs.kind {
                    self.expression(rhs, statement)?;
                    self.emit(opcode::PUSH_TOP, vec![]);
                    self.expression(object, statement)?;
                    self.expression(index, statement)?;
                    self.emit(opcode::LIST_SET, vec![]);
                    return Ok(());
                }
                if let ExprKind::Member {
                    object,
                    selector,
                    via_colon: false,
                } = &lhs.kind
                {
                    if self.variable_expr(object, statement).is_err() {
                        self.expression(rhs, statement)?;
                        self.emit(opcode::PUSH_TOP, vec![]);
                        self.expression(object, statement)?;
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        self.intern_string(selector);
                        self.emit(
                            opcode::SET_VAR,
                            vec![Word::Variable(VariableWord::Field(selector.clone()))],
                        );
                        return Ok(());
                    }
                }
                let var = self.variable_expr(lhs, statement)?;
                self.expression(rhs, statement)?;
                self.emit(opcode::SET_VAR_EXPR, vec![Word::Variable(var)]);
            }
            ExprKind::Binary { op, lhs, rhs } if op == "||=" || op == "&&=" => {
                let variable = self.assignment_variable(lhs, statement)?;
                self.emit(opcode::GET_VAR, vec![Word::Variable(variable.clone())]);
                let end = self.label();
                self.emit(
                    if op == "||=" {
                        opcode::JMP_OR
                    } else {
                        opcode::JMP_AND
                    },
                    vec![Word::Branch(end.clone())],
                );
                self.assignment_value_preserving_cache(&variable, rhs, statement)?;
                self.emit(opcode::SET_VAR_EXPR, vec![Word::Variable(variable)]);
                self.result.code.items.push(CodeItem::Label(end));
            }
            ExprKind::Binary { op, lhs, rhs } if op == "<<=" || op == ">>=" => {
                self.assign_expr(lhs, op, rhs, statement)?;
                self.emit(0x13f, vec![]);
            }
            ExprKind::Binary { op, lhs, rhs }
                if matches!(
                    op.as_str(),
                    "+=" | "-=" | "*=" | "/=" | "%=" | "&=" | "|=" | "^="
                ) =>
            {
                self.assign_expr(lhs, op, rhs, statement)?;
                self.emit(0x13f, vec![]);
            }
            ExprKind::Binary { op, lhs, rhs } => {
                if op == "<<" && is_output_target(lhs) {
                    return Err(error(
                        statement,
                        "output operator requires statement context",
                    ));
                }
                if op == "||" || op == "&&" {
                    let mut tails = vec![rhs.as_ref()];
                    let mut first = lhs.as_ref();
                    while let ExprKind::Binary {
                        op: inner_op,
                        lhs: inner_lhs,
                        rhs: inner_rhs,
                    } = &first.kind
                    {
                        if inner_op != op {
                            break;
                        }
                        tails.push(inner_rhs);
                        first = inner_lhs;
                    }
                    self.expression(first, statement)?;
                    let end = self.label();
                    for next in tails.into_iter().rev() {
                        self.emit(
                            if op == "||" {
                                opcode::JMP_OR
                            } else {
                                opcode::JMP_AND
                            },
                            vec![Word::Branch(end.clone())],
                        );
                        self.expression(next, statement)?;
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                    return Ok(());
                }
                self.expression(lhs, statement)?;
                self.expression(rhs, statement)?;
                let opcode = match op.as_str() {
                    "+" => opcode::ADD,
                    "-" => opcode::SUB,
                    "*" => opcode::MUL,
                    "**" => 0x6a,
                    "/" => opcode::DIV,
                    "%" => opcode::MOD,
                    "==" => opcode::TEQ,
                    "!=" => opcode::TNE,
                    "~=" => 0x140,
                    "~!" => 0x141,
                    "<" => opcode::TL,
                    ">" => opcode::TG,
                    "<=" => opcode::TLE,
                    ">=" => opcode::TGE,
                    "&" => opcode::BAND,
                    "|" => opcode::BOR,
                    "^" => opcode::BXOR,
                    "<<" => opcode::LSHIFT,
                    ">>" => opcode::RSHIFT,
                    _ => return Err(error(statement, "unsupported binary operator")),
                };
                self.emit(opcode, vec![]);
                if op == "==" {
                    self.emit(opcode::POP, vec![]);
                    self.emit(opcode::GET_FLAG, vec![]);
                }
            }
            ExprKind::Call { callee, args } => {
                let named_arguments = args
                    .iter()
                    .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
                let arglist_argument = args.first().filter(|_| args.len() == 1).and_then(|arg| {
                    let ExprKind::Call { callee, args } = &arg.kind else {
                        return None;
                    };
                    (matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist")
                        && args.len() == 1)
                        .then(|| &args[0])
                });
                if let ExprKind::Call {
                    callee: dispatcher,
                    args: target,
                } = &callee.kind
                {
                    if let ExprKind::Ident(dispatcher) = &dispatcher.kind {
                        if dispatcher == "call" || dispatcher == "call_ext" {
                            if !(1..=2).contains(&target.len()) || named_arguments {
                                return Err(error(
                                    statement,
                                    "dynamic call requires target, name, and positional arguments",
                                ));
                            }
                            for target in target {
                                self.expression(target, statement)?;
                            }
                            if let Some(list) = arglist_argument {
                                self.expression(list, statement)?;
                                self.emit(
                                    match (dispatcher.as_str(), target.len()) {
                                        ("call", 1) => 0xcb,
                                        ("call", 2) => 0xcc,
                                        ("call_ext", 1) => 0x17b,
                                        ("call_ext", 2) => 0x117,
                                        _ => unreachable!(),
                                    },
                                    vec![],
                                );
                                return Ok(());
                            }
                            for arg in args {
                                self.expression(arg, statement)?;
                            }
                            self.emit(
                                match (dispatcher.as_str(), target.len()) {
                                    ("call", 1) => 0x2b,
                                    ("call", 2) => 0xb5,
                                    ("call_ext", 1) => 0x17a,
                                    ("call_ext", 2) => 0x116,
                                    _ => unreachable!(),
                                },
                                vec![Word::Immediate(args.len() as u32)],
                            );
                            return Ok(());
                        }
                    }
                }
                if let ExprKind::SafeMember { object, selector } = &callee.kind {
                    let proc_selector = self
                        .expression_member_proc(object, selector)?
                        .map(member_proc_selector)
                        .unwrap_or_else(|| VariableWord::DynamicProc(selector.replace('_', " ")));
                    self.expression(object, statement)?;
                    let end = self.label();
                    self.emit(317, vec![Word::Branch(end.clone())]);
                    self.emit(opcode::PUSH_CACHE, vec![]);
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                    } else if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                    }
                    self.emit(opcode::POP_CACHE, vec![]);
                    if let VariableWord::DynamicProc(display) = &proc_selector {
                        self.intern_string(display);
                    }
                    self.emit(
                        opcode::CALL,
                        vec![
                            Word::Variable(proc_selector),
                            Word::Immediate(if named_arguments || arglist_argument.is_some() {
                                u16::MAX as u32
                            } else {
                                args.len() as u32
                            }),
                        ],
                    );
                    self.result.code.items.push(CodeItem::Label(end));
                    return Ok(());
                }
                if let ExprKind::Member {
                    object, selector, ..
                } = &callee.kind
                {
                    if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                        if !self.has_global_proc(selector)? {
                            return Err(error(
                                statement,
                                &format!("unresolved global procedure: {selector}"),
                            ));
                        }
                        if named_arguments {
                            self.named_arguments(args, statement)?;
                            self.emit(
                                0xcd,
                                vec![Word::Reference(crate::Symbol::new(
                                    crate::Table::Proc,
                                    format!("/proc/{selector}"),
                                ))],
                            );
                        } else {
                            for arg in args {
                                self.expression(arg, statement)?;
                            }
                            self.emit(
                                opcode::CALL_GLOB,
                                vec![
                                    Word::Immediate(args.len() as u32),
                                    Word::Reference(crate::Symbol::new(
                                        crate::Table::Proc,
                                        format!("/proc/{selector}"),
                                    )),
                                ],
                            );
                        }
                        return Ok(());
                    }
                    let proc_selector = self
                        .expression_member_proc(object, selector)?
                        .map(member_proc_selector)
                        .unwrap_or_else(|| VariableWord::DynamicProc(selector.replace('_', " ")));
                    if let VariableWord::DynamicProc(display) = &proc_selector {
                        self.intern_string(display);
                    }
                    let mut safe_labels = Vec::new();
                    if let Ok(owner) = self.variable_expr(object, statement) {
                        if named_arguments {
                            self.named_arguments(args, statement)?;
                        } else if let Some(list) = arglist_argument {
                            self.expression(list, statement)?;
                        } else {
                            for arg in args {
                                self.expression(arg, statement)?;
                            }
                        }
                        self.emit(
                            self.direct_call_opcode(expr),
                            vec![
                                Word::Variable(VariableWord::SetCache(
                                    Box::new(owner),
                                    Box::new(proc_selector.clone()),
                                )),
                                Word::Immediate(if named_arguments || arglist_argument.is_some() {
                                    u16::MAX as u32
                                } else {
                                    args.len() as u32
                                }),
                            ],
                        );
                    } else {
                        self.expression(object, statement)?;
                        safe_labels = self.defer_safe_postfix_labels(object);
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        self.emit(opcode::PUSH_CACHE, vec![]);
                        if named_arguments {
                            self.named_arguments(args, statement)?;
                        } else if let Some(list) = arglist_argument {
                            self.expression(list, statement)?;
                        } else {
                            for arg in args {
                                self.expression(arg, statement)?;
                            }
                        }
                        self.emit(opcode::POP_CACHE, vec![]);
                        self.emit(
                            opcode::CALL,
                            vec![
                                Word::Variable(proc_selector),
                                Word::Immediate(if named_arguments || arglist_argument.is_some() {
                                    u16::MAX as u32
                                } else {
                                    args.len() as u32
                                }),
                            ],
                        );
                    }
                    self.result.code.items.extend(safe_labels);
                    return Ok(());
                }
                let ExprKind::Ident(name) = &callee.kind else {
                    return Err(error(statement, "only simple src proc calls are supported"));
                };
                if matches!(name.as_str(), "cmptext" | "cmptextEx") {
                    if args.len() < 2 || named_arguments || arglist_argument.is_some() {
                        return Err(error(
                            statement,
                            "text comparison requires at least two positional arguments",
                        ));
                    }
                    self.expression(&args[0], statement)?;
                    self.expression(&args[1], statement)?;
                    let comparison = if name == "cmptext" { 0x71 } else { 0x37 };
                    self.emit(comparison, vec![]);
                    let end = self.label();
                    for argument in &args[2..] {
                        self.emit(opcode::JZ, vec![Word::Branch(end.clone())]);
                        self.expression(argument, statement)?;
                        self.emit(comparison, vec![]);
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                    self.emit(opcode::POP, vec![]);
                    self.emit(0x36, vec![]);
                    return Ok(());
                }
                if name == "vector" {
                    if !(1..=3).contains(&args.len())
                        || named_arguments
                        || arglist_argument.is_some()
                    {
                        return Err(error(
                            statement,
                            "vector expects one to three positional arguments",
                        ));
                    }
                    for argument in args {
                        self.expression(argument, statement)?;
                    }
                    self.emit(0x180, vec![Word::Immediate(args.len() as u32)]);
                    return Ok(());
                }
                if name == "gradient" {
                    if args.len() < 2 && arglist_argument.is_none() {
                        return Err(error(statement, "gradient expects at least two arguments"));
                    }
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                    } else if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(opcode::NEW_LIST, vec![Word::Immediate(args.len() as u32)]);
                    }
                    self.emit(0x164, vec![]);
                    return Ok(());
                }
                if name == "statpanel"
                    && args.len() == 1
                    && !named_arguments
                    && arglist_argument.is_none()
                {
                    self.expression(&args[0], statement)?;
                    self.emit(0xa2, vec![]);
                    self.emit(0x36, vec![]);
                    return Ok(());
                }
                if name == "new" {
                    return Err(error(
                        statement,
                        "inferred new requires a typed declaration",
                    ));
                }
                if name == "text" {
                    let Some(Expr {
                        kind: ExprKind::Literal(template),
                        ..
                    }) = args.first()
                    else {
                        return Err(error(statement, "text() requires a literal template"));
                    };
                    if !template.starts_with('"') || !template.ends_with('"') {
                        return Err(error(statement, "text() requires a quoted template"));
                    }
                    let (template, expressions) =
                        parse_text_template(&template[1..template.len() - 1])
                            .map_err(|reason| error(statement, &reason))?;
                    let slots = expressions
                        .iter()
                        .filter(|expression| expression.is_none())
                        .count();
                    if slots != args.len() - 1 {
                        return Err(error(
                            statement,
                            "text() placeholder count differs from arguments",
                        ));
                    }
                    let mut supplied = args[1..].iter();
                    for expression in &expressions {
                        self.expression(
                            expression
                                .as_ref()
                                .unwrap_or_else(|| supplied.next().unwrap()),
                            statement,
                        )?;
                    }
                    let key = self.intern_format_template(template);
                    self.emit(
                        2,
                        vec![
                            Word::Reference(crate::Symbol::new(crate::Table::String, key)),
                            Word::Immediate(expressions.len() as u32),
                        ],
                    );
                    return Ok(());
                }
                if name == "alist" {
                    for arg in args {
                        if let ExprKind::Binary { op, lhs, rhs } = &arg.kind {
                            if op == "=" {
                                self.expression(lhs, statement)?;
                                self.expression(rhs, statement)?;
                                continue;
                            }
                        }
                        self.expression(arg, statement)?;
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(0x17c, vec![Word::Immediate(args.len() as u32)]);
                    return Ok(());
                }
                if name == "generator" {
                    if args.is_empty() {
                        return Err(error(statement, "generator() requires an argument"));
                    }
                    self.intern_string("/generator");
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String("/generator".into()))],
                    );
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                        self.emit(0xcf, vec![]);
                    } else if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                        self.emit(0xcf, vec![]);
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
                    }
                    return Ok(());
                }
                if name == "filter" {
                    if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                    } else {
                        self.named_arguments(args, statement)?;
                    }
                    self.emit(0x13b, vec![]);
                    return Ok(());
                }
                if name == "image" {
                    if args.is_empty() {
                        return Err(error(statement, "image() requires at least one argument"));
                    }
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                        self.emit(0xd3, vec![]);
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(0xd4, vec![Word::Immediate(args.len() as u32)]);
                    }
                    return Ok(());
                }
                if name == "orange" {
                    if args.len() > 2 {
                        return Err(error(statement, "orange() accepts at most two arguments"));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    for _ in args.len()..2 {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(0xad, vec![Word::Immediate(0xae)]);
                    return Ok(());
                }
                if name == "animate" {
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                        self.emit(0x128, vec![]);
                    } else if let Some(target) = args.first() {
                        self.expression(target, statement)?;
                        self.emit(0x129, vec![]);
                    } else {
                        return Err(error(statement, "animate() requires a target"));
                    }
                    return Ok(());
                }
                if name == "pick" {
                    if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                        self.emit(0xd2, vec![]);
                        return Ok(());
                    }
                    if let [arg] = args.as_slice() {
                        if !matches!(&arg.kind, ExprKind::Binary { op, .. } if op == ";") {
                            self.expression(arg, statement)?;
                            self.emit(0xd2, vec![]);
                            return Ok(());
                        }
                    }
                    if args.is_empty() {
                        return Err(error(statement, "pick() requires at least one choice"));
                    }
                    let mut choices = Vec::with_capacity(args.len());
                    let mut total = 0.0_f64;
                    let mut dynamic = false;
                    for arg in args {
                        let (weight_expr, value) = match &arg.kind {
                            ExprKind::Binary { op, lhs, rhs } if op == ";" => {
                                (Some(lhs.as_ref()), rhs.as_ref())
                            }
                            _ => (None, arg),
                        };
                        let weight_expr = weight_expr.map(|weight| {
                            if let ExprKind::Call { callee, args } = &weight.kind {
                                if matches!(&callee.kind, ExprKind::Ident(name) if name == "prob")
                                    && args.len() == 1
                                {
                                    return &args[0];
                                }
                            }
                            weight
                        });
                        let weight = weight_expr.and_then(fold_number).map(f64::from);
                        dynamic |= weight_expr.is_some() && weight.is_none();
                        let weight = weight.unwrap_or(100.0);
                        if !weight.is_finite() || weight < 0.0 {
                            return Err(error(
                                statement,
                                "pick weight must be finite and nonnegative",
                            ));
                        }
                        total += weight;
                        choices.push((weight_expr, weight, value, self.label()));
                    }
                    if !dynamic && total <= 0.0 {
                        return Err(error(statement, "pick weights sum to zero"));
                    }
                    let mut words = vec![Word::Immediate(if dynamic {
                        choices.len() as u32
                    } else {
                        (choices.len() - 1) as u32
                    })];
                    if dynamic {
                        for (weight_expr, _, _, _) in &choices {
                            if let Some(weight_expr) = weight_expr {
                                self.expression(weight_expr, statement)?;
                            } else {
                                self.emit(opcode::PUSH_INT, vec![Word::Immediate(100)]);
                            }
                        }
                        for (_, _, _, label) in &choices {
                            words.push(Word::Branch(label.clone()));
                        }
                        self.emit(0xb1, words);
                    } else {
                        let mut cumulative = 0.0;
                        for (_, weight, _, label) in choices.iter().take(choices.len() - 1) {
                            cumulative += weight;
                            words.push(Word::Immediate(
                                ((cumulative / total) * 65535.0_f64).floor() as u32,
                            ));
                            words.push(Word::Branch(label.clone()));
                        }
                        words.push(Word::Branch(choices.last().unwrap().3.clone()));
                        self.emit(0x79, words);
                    }
                    let end = self.label();
                    for (index, (_, _, value, label)) in choices.iter().enumerate() {
                        self.result.code.items.push(CodeItem::Label(label.clone()));
                        self.expression(value, statement)?;
                        if index + 1 != choices.len() {
                            self.emit(opcode::JMP, vec![Word::Branch(end.clone())]);
                        }
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                    return Ok(());
                }
                if name == "initial" {
                    let [target] = args.as_slice() else {
                        return Err(error(
                            statement,
                            "initial() requires one variable reference",
                        ));
                    };
                    let direct = match &target.kind {
                        ExprKind::Ident(name) => {
                            self.variable(name, statement).ok().filter(|variable| {
                                matches!(
                                    variable,
                                    VariableWord::Arg(_)
                                        | VariableWord::Local(_)
                                        | VariableWord::Global(_)
                                )
                            })
                        }
                        ExprKind::Member { object, .. } if matches!(&object.kind, ExprKind::Ident(name) if name == "global") => {
                            Some(self.variable_expr(target, statement)?)
                        }
                        _ => None,
                    };
                    if let Some(variable) = direct {
                        self.emit(
                            opcode::GET_VAR,
                            vec![Word::Variable(VariableWord::Initial(Box::new(variable)))],
                        );
                        return Ok(());
                    }
                    if matches!(&target.kind, ExprKind::Index { .. }) {
                        let variable = self.assignment_variable(target, statement)?;
                        self.emit(
                            opcode::GET_VAR,
                            vec![Word::Variable(VariableWord::Initial(Box::new(variable)))],
                        );
                        return Ok(());
                    }
                    if let ExprKind::StaticMember { object, selector } = &target.kind {
                        let ExprKind::TypePath(path) = &object.kind else {
                            return Err(error(
                                statement,
                                "qualified initial() requires a captured type path",
                            ));
                        };
                        if let Some(lookup) = self.lookup {
                            if !self.semantic(lookup.presence(
                                dm_ir::ResolveQuery::HasMemberVar {
                                    owner: dm_ir::SymbolId::of(path),
                                    name: dm_ir::SymbolId::of(selector),
                                },
                            ))? {
                                return Err(error(
                                    statement,
                                    "qualified initial() field is absent",
                                ));
                            }
                        }
                        // The pinned compiler uses the same static-reference
                        // selector as /type::field, rather than Initial(Global).
                        self.expression(target, statement)?;
                        return Ok(());
                    }
                    let (owner, selector) = match &target.kind {
                        ExprKind::Ident(field) if self.has_field(field)? => {
                            (Some(VariableWord::Src), field.clone())
                        }
                        ExprKind::Member {
                            object,
                            selector,
                            via_colon: _,
                        } => (self.variable_expr(object, statement).ok(), selector.clone()),
                        _ => return Err(error(statement, "initial() requires a field reference")),
                    };
                    self.intern_string(&selector);
                    if let Some(owner) = owner {
                        self.emit(
                            opcode::GET_VAR,
                            vec![Word::Variable(VariableWord::SetCache(
                                Box::new(owner),
                                Box::new(VariableWord::StaticField(selector)),
                            ))],
                        );
                    } else if let ExprKind::Member { object, .. } = &target.kind {
                        self.expression(object, statement)?;
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        self.emit(
                            opcode::GET_VAR,
                            vec![Word::Variable(VariableWord::StaticField(selector))],
                        );
                    }
                    return Ok(());
                }
                if name == "issaved" {
                    let [target] = args.as_slice() else {
                        return Err(error(
                            statement,
                            "issaved() requires one variable reference",
                        ));
                    };
                    let variable = self.assignment_variable(target, statement)?;
                    let variable = match variable {
                        VariableWord::SetCache(owner, field) => {
                            VariableWord::SetCache(owner, Box::new(VariableWord::IsSaved(field)))
                        }
                        other => VariableWord::IsSaved(Box::new(other)),
                    };
                    self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                    return Ok(());
                }
                if name == "arglist" {
                    return Err(error(
                        statement,
                        "built-in reference form is not lowered in this context",
                    ));
                }
                if name == "istype" {
                    let target_type = match args.as_slice() {
                        [value, path] => {
                            self.expression(value, statement)?;
                            self.expression(path, statement)?;
                            self.emit(0x7d, vec![]);
                            return Ok(());
                        }
                        [value] => self.inferred_expression_type(value)?,
                        _ => {
                            return Err(error(statement, "istype() requires one or two arguments"))
                        }
                    }
                    .ok_or_else(|| error(statement, "istype() cannot infer a declared type"))?;
                    self.expression(&args[0], statement)?;
                    let tag = self
                        .class_tag(&target_type)?
                        .ok_or_else(|| error(statement, "istype() inferred unsupported type"))?;
                    if self.seen_classes.insert(target_type.clone()) {
                        self.result.class_paths.push(target_type.clone());
                    }
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ClassPath {
                            path: target_type,
                            tag,
                        })],
                    );
                    self.emit(0x7d, vec![]);
                    return Ok(());
                }
                if name == "del" {
                    return Err(error(statement, "del() requires statement context"));
                }
                if name == "input" {
                    return self.input_call(args, &[], None, statement);
                }
                if name == "nameof" {
                    let [arg] = args.as_slice() else {
                        return Err(error(statement, "nameof() requires one reference"));
                    };
                    let leaf = nameof_reference(arg).ok_or_else(|| {
                        error(
                            statement,
                            "nameof() requires a variable, procedure, or type reference",
                        )
                    })?;
                    self.intern_string(leaf);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(leaf.into()))],
                    );
                    return Ok(());
                }
                if name == "rgb" && args.len() == 4 {
                    if let ExprKind::Binary { op, lhs, rhs } = &args[3].kind {
                        if op == "=" && matches!(&lhs.kind, ExprKind::Ident(key) if key == "space")
                        {
                            for arg in &args[..3] {
                                if let ExprKind::Binary { op, rhs, .. } = &arg.kind {
                                    if op == "=" {
                                        self.expression(rhs, statement)?;
                                        continue;
                                    }
                                }
                                self.expression(arg, statement)?;
                            }
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                            self.expression(rhs, statement)?;
                            self.emit(0x161, vec![]);
                            return Ok(());
                        }
                    }
                }
                if named_arguments
                    && name != "list"
                    && name != "icon"
                    && (crate::builtin_catalog::lookup(name).is_some()
                        || matches!(
                            name.as_str(),
                            "rand"
                                | "regex"
                                | "copytext"
                                | "findtext"
                                | "clamp"
                                | "min"
                                | "max"
                                | "isnull"
                                | "ceil"
                                | "floor"
                                | "round"
                                | "length"
                                | "text2num"
                                | "file"
                                | "sleep"
                        ))
                {
                    return Err(error(statement, "named built-in arguments are not lowered"));
                }
                if name == "." {
                    if let [arg] = args.as_slice() {
                        if let ExprKind::Call {
                            callee,
                            args: list_args,
                        } = &arg.kind
                        {
                            if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                                if list_args.len() != 1 {
                                    return Err(error(
                                        statement,
                                        "arglist() requires one argument",
                                    ));
                                }
                                self.expression(&list_args[0], statement)?;
                                self.emit(0xca, vec![]);
                                return Ok(());
                            }
                        }
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x2f, vec![Word::Immediate(args.len() as u32)]);
                    return Ok(());
                }
                if name == "rand" {
                    if args.len() > 2 {
                        return Err(error(statement, "rand() accepts at most two arguments"));
                    }
                    if args.is_empty() {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                    }
                    self.emit(if args.len() == 2 { 0x23 } else { 0x22 }, vec![]);
                    return Ok(());
                }
                if name == "isnull" {
                    if args.len() != 1 {
                        return Err(error(statement, "isnull() requires one argument"));
                    }
                    self.expression(&args[0], statement)?;
                    self.emit(opcode::IS_NULL, vec![]);
                    return Ok(());
                }
                if name == "ceil" {
                    if args.len() != 1 {
                        return Err(error(statement, "ceil() requires one argument"));
                    }
                    self.expression(&args[0], statement)?;
                    self.emit(0x169, vec![]);
                    return Ok(());
                }
                if name == "floor" {
                    if args.len() != 1 {
                        return Err(error(statement, "floor() requires one argument"));
                    }
                    self.expression(&args[0], statement)?;
                    self.emit(0x43, vec![]);
                    return Ok(());
                }
                if name == "round" {
                    if !(1..=2).contains(&args.len()) {
                        return Err(error(statement, "round() requires one or two arguments"));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(if args.len() == 1 { 0x43 } else { 0x44 }, vec![]);
                    return Ok(());
                }
                if name == "regex" {
                    if !(1..=2).contains(&args.len()) {
                        return Err(error(statement, "regex() requires one or two arguments"));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x13a, vec![Word::Immediate(args.len() as u32)]);
                    return Ok(());
                }
                if name == "length" {
                    if args.len() != 1 {
                        return Err(error(statement, "length() requires one argument"));
                    }
                    self.expression(&args[0], statement)?;
                    self.emit(0x6d, vec![]);
                    return Ok(());
                }
                if name == "copytext" {
                    if !(2..=3).contains(&args.len()) {
                        return Err(error(
                            statement,
                            "copytext() requires two or three arguments",
                        ));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    if args.len() == 2 {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(0x6e, vec![]);
                    return Ok(());
                }
                if name == "text2num" {
                    if !(1..=2).contains(&args.len()) {
                        return Err(error(statement, "text2num() requires one or two arguments"));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(if args.len() == 1 { 0x76 } else { 0x158 }, vec![]);
                    return Ok(());
                }
                if name == "findtext" {
                    if !(2..=4).contains(&args.len()) {
                        return Err(error(
                            statement,
                            "findtext() requires two to four arguments",
                        ));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    if args.len() == 2 {
                        self.emit(opcode::PUSH_INT, vec![Word::Immediate(1)]);
                    }
                    if args.len() < 4 {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(0x6f, vec![]);
                    return Ok(());
                }
                if name == "clamp" {
                    if args.len() != 3 {
                        return Err(error(statement, "clamp() requires three arguments"));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x14a, vec![]);
                    return Ok(());
                }
                if name == "min" || name == "max" {
                    if args.is_empty() {
                        return Err(error(statement, "min/max require at least one argument"));
                    }
                    if let [arg] = args.as_slice() {
                        if let ExprKind::Call {
                            callee,
                            args: list_args,
                        } = &arg.kind
                        {
                            if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                                if list_args.len() != 1 {
                                    return Err(error(
                                        statement,
                                        "arglist() requires one argument",
                                    ));
                                }
                                self.expression(&list_args[0], statement)?;
                                self.emit(if name == "min" { 0xd0 } else { 0xd1 }, vec![]);
                                return Ok(());
                            }
                        }
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    if args.len() == 1 {
                        self.emit(if name == "min" { 0xd0 } else { 0xd1 }, vec![]);
                    } else {
                        self.emit(
                            if name == "min" { 0xa5 } else { 0xa6 },
                            vec![Word::Immediate(args.len() as u32)],
                        );
                    }
                    return Ok(());
                }
                if name == "file" {
                    if args.len() != 1 {
                        return Err(error(statement, "file() requires one positional argument"));
                    }
                    self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::FileType)]);
                    self.expression(&args[0], statement)?;
                    self.emit(opcode::NEW, vec![Word::Immediate(1)]);
                    return Ok(());
                }
                if name == "icon" || name == "sound" {
                    if args.len() > 255 {
                        return Err(error(statement, "constructor has too many arguments"));
                    }
                    let class_path = if name == "icon" { "/icon" } else { "/sound" };
                    self.intern_string(class_path);
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::String(class_path.into()))],
                    );
                    let named = args
                        .iter()
                        .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
                    if named {
                        self.named_arguments(args, statement)?;
                        self.emit(0xcf, vec![]);
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(opcode::NEW, vec![Word::Immediate(args.len() as u32)]);
                    }
                    return Ok(());
                }
                if name == "newlist" {
                    if named_arguments {
                        return Err(error(
                            statement,
                            "newlist() does not accept named arguments",
                        ));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                        self.emit(opcode::NEW, vec![Word::Immediate(0)]);
                    }
                    self.emit(opcode::NEW_LIST, vec![Word::Immediate(args.len() as u32)]);
                    return Ok(());
                }
                if name == "list" {
                    let associative = args
                        .iter()
                        .any(|arg| matches!(&arg.kind, ExprKind::Binary { op, .. } if op == "="));
                    if associative {
                        self.named_arguments(args, statement)?;
                        return Ok(());
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    // EMPTY_LIST consumes a dimension from the stack. A literal
                    // list(), including arglist(list()), has zero operands.
                    self.emit(opcode::NEW_LIST, vec![Word::Immediate(args.len() as u32)]);
                    return Ok(());
                }
                if name == ".." {
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                        self.emit(0xc9, vec![]);
                    } else if args.is_empty() {
                        self.emit(0x2c, vec![]);
                    } else if let [arg] = args.as_slice() {
                        if let ExprKind::Call {
                            callee,
                            args: list_args,
                        } = &arg.kind
                        {
                            if matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist") {
                                if list_args.len() != 1 {
                                    return Err(error(
                                        statement,
                                        "arglist() requires one argument",
                                    ));
                                }
                                self.expression(&list_args[0], statement)?;
                                self.emit(0xc9, vec![]);
                                return Ok(());
                            }
                        }
                        self.expression(arg, statement)?;
                        self.emit(0x2d, vec![Word::Immediate(1)]);
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                        self.emit(0x2d, vec![Word::Immediate(args.len() as u32)]);
                    }
                    return Ok(());
                }
                if name == "sleep" {
                    return Err(error(statement, "sleep requires statement lowering"));
                }
                if name == "alert" {
                    if !(1..=6).contains(&args.len()) {
                        return Err(error(statement, "alert() requires one to six arguments"));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    for _ in args.len()..6 {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    self.emit(0x18, vec![]);
                    return Ok(());
                }
                if name == "time2text" && args.len() == 3 {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x15d, vec![Word::Immediate(3)]);
                    return Ok(());
                }
                if name == "json_encode" && args.len() == 2 {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(0x167, vec![Word::Immediate(2)]);
                    return Ok(());
                }
                let alternate_opcode = match (name.as_str(), args.len()) {
                    ("arctan", 2) => Some(0x146),
                    ("log", 2) => Some(0x32),
                    ("num2text", 2) => Some(0x56),
                    ("num2text", 3) => Some(0x159),
                    ("ispath", 2) => Some(0xf6),
                    ("locate", 2) => Some(0x97),
                    ("locate", 3) => Some(0x5a),
                    ("rgb", 4) => Some(0x113),
                    _ => None,
                };
                if let Some(opcode) = alternate_opcode {
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(opcode, vec![]);
                    return Ok(());
                }
                if let Some(spec) = crate::builtin_catalog::lookup_with_arity(name, args.len()) {
                    if !(spec.min_args..=spec.max_args).contains(&args.len()) {
                        return Err(error(
                            statement,
                            &format!(
                                "invalid built-in argument count: {name} got {} expected {}..={}",
                                args.len(),
                                spec.min_args,
                                spec.max_args
                            ),
                        ));
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    let omitted = if spec.max_args == usize::MAX {
                        0
                    } else {
                        spec.max_args - args.len()
                    };
                    if omitted > spec.trailing_defaults.len() {
                        return Err(error(statement, "missing built-in default arguments"));
                    }
                    for default in &spec.trailing_defaults[spec.trailing_defaults.len() - omitted..]
                    {
                        if let ValueWord::Number(bits) = default {
                            let number = f32::from_bits(*bits);
                            if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                                self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
                                continue;
                            }
                        }
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(default.clone())]);
                    }
                    let operands = match spec.count_operand {
                        crate::builtin_catalog::OpcodeCountPolicy::None => vec![],
                        crate::builtin_catalog::OpcodeCountPolicy::EmittedArgs => {
                            vec![Word::Immediate(args.len() as u32)]
                        }
                        crate::builtin_catalog::OpcodeCountPolicy::Fixed(value) => {
                            vec![Word::Immediate(value)]
                        }
                    };
                    self.emit(spec.opcode, operands);
                    if let Some(post_opcode) = spec.post_opcode {
                        self.emit(post_opcode, vec![]);
                    }
                    if crate::builtin_catalog::is_void(name) {
                        self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Null)]);
                    }
                    return Ok(());
                }
                let has_member_proc = self.current_has_declared_member_proc(name)?
                    || self.current_member_proc(name)?.is_some();
                if !has_member_proc && self.has_global_proc(name)? {
                    if named_arguments || arglist_argument.is_some() {
                        if named_arguments {
                            self.named_arguments(args, statement)?;
                        } else if let Some(list) = arglist_argument {
                            self.expression(list, statement)?;
                        }
                        self.emit(
                            0xcd,
                            vec![Word::Reference(crate::Symbol::new(
                                crate::Table::Proc,
                                format!("/proc/{name}"),
                            ))],
                        );
                        return Ok(());
                    }
                    for arg in args {
                        self.expression(arg, statement)?;
                    }
                    self.emit(
                        opcode::CALL_GLOB,
                        vec![
                            Word::Immediate(args.len() as u32),
                            Word::Reference(crate::Symbol::new(
                                crate::Table::Proc,
                                format!("/proc/{name}"),
                            )),
                        ],
                    );
                    return Ok(());
                }
                if matches!(
                    name.as_str(),
                    "sound"
                        | "image"
                        | "animate"
                        | "locate"
                        | "pick"
                        | "issaved"
                        | "typesof"
                        | "istype"
                        | "islist"
                        | "istext"
                        | "isnum"
                        | "ispath"
                        | "isfile"
                        | "get_turf"
                        | "hascall"
                        | "call"
                        | "filter"
                        | "generator"
                        | "alert"
                        | "input"
                        | "text2path"
                        | "json_encode"
                        | "json_decode"
                ) {
                    return Err(error(statement, "unlowered built-in call"));
                }
                {
                    let proc_selector = self
                        .current_member_proc(name)?
                        .map(member_proc_selector)
                        .unwrap_or_else(|| VariableWord::DynamicProc(name.replace('_', " ")));
                    if (self.lookup.is_some() || self.bindings.shared.is_some())
                        && matches!(proc_selector, VariableWord::DynamicProc(_))
                        && !self.current_has_declared_member_proc(name)?
                    {
                        return Err(error(
                            statement,
                            &format!("unresolved unqualified procedure: {name}"),
                        ));
                    }
                    if let VariableWord::DynamicProc(display) = &proc_selector {
                        self.intern_string(display);
                    }
                    if named_arguments {
                        self.named_arguments(args, statement)?;
                    } else if let Some(list) = arglist_argument {
                        self.expression(list, statement)?;
                    } else {
                        for arg in args {
                            self.expression(arg, statement)?;
                        }
                    }
                    self.emit(
                        self.direct_call_opcode(expr),
                        vec![
                            Word::Variable(VariableWord::SetCache(
                                Box::new(VariableWord::Src),
                                Box::new(proc_selector),
                            )),
                            Word::Immediate(if named_arguments || arglist_argument.is_some() {
                                u16::MAX as u32
                            } else {
                                args.len() as u32
                            }),
                        ],
                    );
                }
            }
        }
        Ok(())
    }
}

fn member_proc_selector(path: String) -> VariableWord {
    if path.contains("/verb/") {
        VariableWord::StaticVerb(path)
    } else {
        VariableWord::StaticProc(path)
    }
}

fn class_tag(path: &str) -> Option<u8> {
    let root = path.trim_start_matches('/').split('/').next()?;
    Some(match root {
        "datum" | "regex" | "icon" | "sound" | "matrix" | "particles" | "database"
        | "generator" | "exception" => 32,
        "obj" | "atom" => 9,
        "mob" => 8,
        "turf" => 10,
        "area" => 11,
        "client" => 59,
        "image" | "mutable_appearance" => 63,
        "list" => 40,
        "alist" => 89,
        "savefile" => 36,
        "file" => 39,
        _ => return None,
    })
}

/// Compile-time spelling of a DM reference. Its receiver is not evaluated.
pub fn nameof_reference(expr: &Expr) -> Option<&str> {
    match &expr.kind {
        ExprKind::Ident(name) => Some(name),
        ExprKind::TypePath(path) => path.rsplit('/').next().filter(|name| !name.is_empty()),
        ExprKind::Member { selector, .. } | ExprKind::StaticMember { selector, .. } => {
            Some(selector)
        }
        ExprKind::Group(inner) => nameof_reference(inner),
        _ => None,
    }
}

fn error(statement: &str, reason: &str) -> LowerError {
    LowerError {
        statement: statement.into(),
        reason: reason.into(),
        ..LowerError::default()
    }
}

fn parenthesized(text: &str) -> Option<&str> {
    let open = text.find('(')?;
    text.ends_with(')')
        .then_some(&text[open + 1..text.len() - 1])
}

/// Decode a quoted DM literal using the same escapes as procedure lowering.
/// Interpolated literals require runtime evaluation and return `None`.
pub fn decode_constant_string_literal(raw: &str) -> Result<Option<Vec<u8>>, String> {
    // Raw literals preserve escapes and brackets exactly, including multiline text.
    let raw_value = if raw.starts_with("@{\"") && raw.ends_with("\"}") && raw.len() >= 5 {
        Some(&raw[3..raw.len() - 2])
    } else if ((raw.starts_with("@\"") && raw.ends_with('"'))
        || (raw.starts_with("@'") && raw.ends_with('\'')))
        && raw.len() >= 3
    {
        Some(&raw[2..raw.len() - 1])
    } else {
        None
    };
    if let Some(value) = raw_value {
        return Ok(Some(value.as_bytes().to_vec()));
    }
    let value = if raw.starts_with("{\"") && raw.ends_with("\"}") && raw.len() >= 4 {
        &raw[2..raw.len() - 2]
    } else if raw.starts_with('"') && raw.ends_with('"') && raw.len() >= 2 {
        &raw[1..raw.len() - 1]
    } else {
        return Ok(None);
    };
    let (bytes, expressions) = parse_interpolated_string(value)?;
    Ok(expressions.is_empty().then_some(bytes))
}

fn parse_interpolated_string(value: &str) -> Result<(Vec<u8>, Vec<Expr>), String> {
    let mut template = Vec::new();
    let mut expressions = Vec::new();
    let mut next_marker = None;
    let mut at = 0;
    while at < value.len() {
        let ch = value[at..].chars().next().unwrap();
        if ch == '\\' {
            at += 1;
            let rest = &value[at..];
            if rest.starts_with("\r\n") || rest.starts_with('\n') {
                at += if rest.starts_with("\r\n") { 2 } else { 1 };
                while at < value.len() && matches!(value.as_bytes()[at], b' ' | b'\t') {
                    at += 1;
                }
                continue;
            }
            if rest.starts_with(' ') {
                at += 1;
                continue;
            }
            if rest.starts_with('x') && rest.len() >= 3 {
                let hex = &rest[1..3];
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    let mut encoded = [0; 4];
                    template
                        .extend_from_slice(char::from(byte).encode_utf8(&mut encoded).as_bytes());
                    at += 3;
                    continue;
                }
            }
            let control = [
                ("improper", 0x16, false, true),
                ("proper", 0x15, false, true),
                ("himself", 0x11, false, false),
                ("hers", 0x0e, false, false),
                ("The", 0x09, true, true),
                ("the", 0x08, true, true),
                ("his", 0x0c, false, false),
                ("he", 0x0a, false, false),
                ("A", 0x07, true, true),
                ("a", 0x06, true, true),
                ("ref", 0x2a, true, false),
                ("roman", 0x2c, true, false),
                ("Roman", 0x2d, true, false),
                ("th", 0x05, false, false),
                ("s", 0x14, false, false),
            ]
            .into_iter()
            .find(|(name, ..)| rest.starts_with(name));
            if let Some((name, marker, modifies_next, consumes_space)) = control {
                if modifies_next && !consumes_space {
                    next_marker = Some(marker);
                } else {
                    template.extend([0xff, marker]);
                    if modifies_next {
                        next_marker = Some(0x03);
                    }
                }
                at += name.len();
                if consumes_space && value[at..].starts_with(' ') {
                    at += 1;
                }
                continue;
            }
            let escape = value[at..].chars().next().ok_or("trailing string escape")?;
            let escaped = match escape {
                'n' => "\n",
                'r' => "\r",
                't' => "\t",
                '\\' => "\\",
                '"' => "\"",
                '\'' => "'",
                '[' => "[",
                ']' => "]",
                '<' => "&lt;",
                '>' => "&gt;",
                '&' => "&amp;",
                _ => return Err(format!("unsupported string escape: \\{escape}")),
            };
            template.extend_from_slice(escaped.as_bytes());
            at += escape.len_utf8();
            continue;
        }
        if ch == '[' {
            let start = at + 1;
            let mut cursor = start;
            let mut depth = 1usize;
            let mut quote = false;
            while cursor < value.len() {
                let next = value[cursor..].chars().next().unwrap();
                if next == '"' {
                    quote = !quote;
                }
                if !quote {
                    if next == '[' {
                        depth += 1;
                    }
                    if next == ']' {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                    }
                }
                cursor += next.len_utf8();
            }
            if depth != 0 {
                return Err("unclosed string interpolation".into());
            }
            if value[start..cursor].trim().is_empty() {
                template.extend([0xff, next_marker.take().unwrap_or(1)]);
                at = cursor + 1;
                continue;
            }
            let expression = parse_expression(value[start..cursor].trim());
            if !expression.diagnostics.is_empty() {
                return Err("invalid string interpolation expression".into());
            }
            expressions.push(expression.expr.ok_or("empty string interpolation")?);
            let marker = next_marker.take().unwrap_or_else(|| {
                if interpolation_starts_sentence(&template) {
                    2
                } else {
                    1
                }
            });
            template.extend([0xff, marker]);
            at = cursor + 1;
            continue;
        }
        let mut bytes = [0; 4];
        template.extend_from_slice(ch.encode_utf8(&mut bytes).as_bytes());
        at += ch.len_utf8();
    }
    Ok((template, expressions))
}

fn parse_text_template(value: &str) -> Result<(Vec<u8>, Vec<Option<Expr>>), String> {
    let mut expanded = String::with_capacity(value.len());
    let mut slots = 0;
    let mut chars = value.chars().peekable();
    while let Some(ch) = chars.next() {
        if ch == '\\' {
            expanded.push(ch);
            if let Some(escaped) = chars.next() {
                expanded.push(escaped);
            }
            continue;
        }
        if ch == '[' && chars.peek() == Some(&']') {
            chars.next();
            expanded.push_str(&format!("[__dm_text_slot_{slots}__]"));
            slots += 1;
        } else {
            expanded.push(ch);
        }
    }
    let (template, expressions) = parse_interpolated_string(&expanded)?;
    let expressions = expressions
        .into_iter()
        .map(|expression| match &expression.kind {
            ExprKind::Ident(name) if name.starts_with("__dm_text_slot_") => None,
            _ => Some(expression),
        })
        .collect();
    Ok((template, expressions))
}

fn interpolation_starts_sentence(mut prefix: &[u8]) -> bool {
    loop {
        while prefix
            .last()
            .is_some_and(|byte| matches!(byte, b' ' | b'\n' | b'\t' | b'\'' | b'"'))
        {
            prefix = &prefix[..prefix.len() - 1];
        }
        match prefix.last() {
            None | Some(b'.' | b'!' | b'?') => return true,
            Some(b'>') => {
                if let Some(opening) = prefix.iter().rposition(|byte| *byte == b'<') {
                    prefix = &prefix[..opening];
                } else {
                    return true;
                }
            }
            _ => return false,
        }
    }
}

fn fold_number(expr: &Expr) -> Option<f32> {
    match &expr.kind {
        ExprKind::Literal(value) if value == "1.#INF" => Some(f32::INFINITY),
        ExprKind::Literal(value) if value.starts_with("0x") || value.starts_with("0X") => {
            u64::from_str_radix(&value[2..].replace('_', ""), 16)
                .ok()
                .map(|number| number as f32)
        }
        ExprKind::Literal(value) => value.parse().ok(),
        ExprKind::Unary { op, value } if op == "-" => Some(-fold_number(value)?),
        ExprKind::Group(value) => fold_number(value),
        ExprKind::Binary { op, lhs, rhs } => {
            let a = fold_number(lhs)?;
            let b = fold_number(rhs)?;
            Some(match op.as_str() {
                "+" => a + b,
                "-" => a - b,
                "*" => a * b,
                "/" if b != 0.0 => a / b,
                "%" if a.is_finite()
                    && b.is_finite()
                    && a >= i32::MIN as f32
                    && a < 2_147_483_648.0
                    && b >= i32::MIN as f32
                    && b < 2_147_483_648.0 =>
                {
                    // DM's % truncates both operands; %% is the real-valued
                    // modulo operator. Checked remainder avoids zero/overflow.
                    (a as i32).checked_rem(b as i32)? as f32
                }
                "<<" if a.is_finite()
                    && b.is_finite()
                    && a.fract() == 0.0
                    && b.fract() == 0.0
                    && a >= i32::MIN as f32
                    && a < 2_147_483_648.0
                    && (0.0..32.0).contains(&b) =>
                {
                    ((a.max(0.0) as u32).wrapping_shl(b as u32) & 0x00ff_ffff) as f32
                }
                ">>" if a.is_finite()
                    && b.is_finite()
                    && a.fract() == 0.0
                    && b.fract() == 0.0
                    && a >= i32::MIN as f32
                    && a < 2_147_483_648.0
                    && (0.0..32.0).contains(&b) =>
                {
                    ((a as i32 & 0x00ff_ffff) as u32).wrapping_shr(b as u32) as f32
                }
                _ => return None,
            })
        }
        _ => None,
    }
}

#[cfg(test)]
#[path = "dynamic_selector_tests.rs"]
mod dynamic_selector_tests;

#[cfg(test)]
#[path = "simple/tests/mod.rs"]
mod tests;
