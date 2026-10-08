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

#[path = "simple/assignments.rs"]
mod assignments;
#[path = "simple/calls_dispatch.rs"]
mod calls_dispatch;
#[path = "simple/calls_general.rs"]
mod calls_general;
#[path = "simple/calls_intrinsics.rs"]
mod calls_intrinsics;
#[path = "simple/emission.rs"]
mod emission;
#[path = "simple/expression.rs"]
mod expression;
#[path = "simple/helpers.rs"]
mod helpers;
#[path = "simple/inference.rs"]
mod inference;
#[path = "simple/resolution.rs"]
mod resolution;
#[path = "simple/statements.rs"]
mod statements;
#[path = "simple/typed_statements.rs"]
mod typed_statements;
use helpers::{
    class_tag, error, fold_number, member_proc_selector, parenthesized, parse_interpolated_string,
    parse_text_template,
};
pub use helpers::{decode_constant_string_literal, nameof_reference};

#[cfg(test)]
#[path = "dynamic_selector_tests.rs"]
mod dynamic_selector_tests;

#[cfg(test)]
#[path = "simple/tests/mod.rs"]
mod tests;
