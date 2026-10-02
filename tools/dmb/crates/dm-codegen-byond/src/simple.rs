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

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct LowerError {
    pub statement: String,
    pub reason: String,
    #[serde(default)]
    pub statement_origin: Option<crate::debug::RelativeStatementSpan>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
pub struct SimpleProc {
    pub code: SymbolicProc,
    /// Body-relative anchors resolved to current preprocessor origins at link.
    #[serde(default)]
    pub statement_origins: Vec<crate::debug::StatementOrigin>,
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
pub struct OwnerLowerBindings {
    pub fields: im::OrdSet<String>,
    pub field_types: im::OrdMap<String, String>,
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct LowerBindings {
    /// Canonical path of the procedure being lowered, for compiler context values.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_proc_path: Option<String>,
    /// Canonical owner path, absent for global procedures.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_type_path: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub parameters: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub parameter_type_flags: Vec<u32>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub parameter_value_sources: Vec<u32>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub parameter_defaults: Vec<Option<String>>,
    /// Declared parameter paths for type-inferred built-ins such as `istype(x)`.
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub parameter_types: HashMap<String, String>,
    #[serde(skip_serializing_if = "BTreeSet::is_empty")]
    pub fields: BTreeSet<String>,
    #[serde(skip_serializing_if = "BTreeSet::is_empty")]
    pub globals: BTreeSet<String>,
    /// Declared type paths used to resolve `new(args)` without an explicit path.
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub field_types: HashMap<String, String>,
    /// Immutable inherited owner frame shared by procedures on the same type.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub owner: Option<Arc<OwnerLowerBindings>>,
    /// Proc-local static names shadow owner fields without copying the owner set.
    #[serde(skip_serializing_if = "BTreeSet::is_empty")]
    pub hidden_owner_fields: BTreeSet<String>,
    #[serde(skip_serializing_if = "HashMap::is_empty")]
    pub global_types: HashMap<String, String>,
    /// Global procedure names resolvable to ProcIDs at link time.
    #[serde(skip_serializing_if = "BTreeSet::is_empty")]
    pub global_procs: BTreeSet<String>,
    /// Immutable project-wide names shared between procedure lowering jobs.
    #[serde(skip)]
    pub shared: Option<Arc<SharedLowerBindings>>,
    /// Invocation-local accelerator prepared once for this exact shared Arc.
    /// Opaque cache state is absent from serialization and semantic equality.
    #[serde(skip)]
    pub prepared_member_globals: crate::PreparedMemberGlobals,
}

#[cfg(test)]
mod binding_codec_tests {
    use super::*;

    #[test]
    fn compact_frames_preserve_parameters_and_static_shadowing() {
        assert_eq!(serde_json::to_string(&LowerBindings::default()).unwrap(), "{}");
        let bindings = LowerBindings {
            current_proc_path: Some("/datum/holder/proc/test".into()),
            current_type_path: Some("/datum/holder".into()),
            parameters: vec!["actor".into()],
            parameter_type_flags: vec![8],
            parameter_value_sources: vec![0x7d01],
            parameter_defaults: vec![None],
            parameter_types: HashMap::from([("actor".into(), "/mob".into())]),
            globals: BTreeSet::from(["value".into()]),
            hidden_owner_fields: BTreeSet::from(["value".into()]),
            owner: Some(Arc::new(OwnerLowerBindings {
                fields: ["value".into()].into_iter().collect(),
                field_types: Default::default(),
            })),
            ..LowerBindings::default()
        };
        let bytes = serde_json::to_vec(&bindings).unwrap();
        assert_eq!(serde_json::from_slice::<LowerBindings>(&bytes).unwrap(), bindings);
    }
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
    /// Explicit concrete source return annotations. Unannotated overrides
    /// inherit the return declaration from their parent procedure.
    #[serde(default)]
    pub global_proc_return_types: HashMap<String, String>,
    #[serde(default)]
    pub member_proc_return_types: HashMap<String, HashMap<String, String>>,
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
    pub fn hide_owner_field(&mut self, name: &str) {
        self.fields.remove(name);
        self.hidden_owner_fields.insert(name.to_owned());
    }
    fn has_field(&self, name: &str) -> bool {
        let result = self.has_field_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::Field(name.into()),
            crate::FactValue::Boolean(result),
        );
        result
    }
    fn has_global(&self, name: &str) -> bool {
        let result = self.has_global_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::Global(name.into()),
            crate::FactValue::Boolean(result),
        );
        result
    }
    fn has_global_proc(&self, name: &str) -> bool {
        let result = self.has_global_proc_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::GlobalProc(name.into()),
            crate::FactValue::Boolean(result),
        );
        result
    }
    fn field_type(&self, name: &str) -> Option<&str> {
        let result = self.field_type_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::FieldType(name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn global_type(&self, name: &str) -> Option<&str> {
        let result = self.global_type_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::GlobalType(name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn member_type(&self, owner: &str, name: &str) -> Option<&str> {
        let result = self.member_type_raw(owner, name);
        crate::dependencies::observe(
            crate::BindingFact::MemberType(owner.into(), name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn member_global(&self, owner: &str, name: &str) -> Option<&str> {
        let result = self.member_global_raw(owner, name);
        crate::dependencies::observe(
            crate::BindingFact::MemberGlobal(owner.into(), name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn unique_member_global(&self, name: &str) -> Option<&str> {
        let result = self.unique_member_global_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::UniqueMemberGlobal(name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn member_proc(&self, owner: &str, name: &str) -> Option<&str> {
        let result = self.member_proc_raw(owner, name);
        crate::dependencies::observe(
            crate::BindingFact::MemberProc(owner.into(), name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn has_declared_member_proc(&self, owner: &str, name: &str) -> bool {
        let result = self.has_declared_member_proc_raw(owner, name);
        crate::dependencies::observe(
            crate::BindingFact::DeclaredMemberProc(owner.into(), name.into()),
            crate::FactValue::Boolean(result),
        );
        result
    }
    fn global_proc_return_type(&self, name: &str) -> Option<&str> {
        let result = self.global_proc_return_type_raw(name);
        crate::dependencies::observe(
            crate::BindingFact::GlobalProcReturnType(name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn member_proc_return_type(&self, owner: &str, name: &str) -> Option<&str> {
        let result = self.member_proc_return_type_raw(owner, name, false);
        crate::dependencies::observe(
            crate::BindingFact::MemberProcReturnType(owner.into(), name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn parent_proc_return_type(&self, owner: &str, name: &str) -> Option<&str> {
        let result = self.member_proc_return_type_raw(owner, name, true);
        crate::dependencies::observe(
            crate::BindingFact::ParentProcReturnType(owner.into(), name.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn modified_instance(&self, path: &str) -> Option<&str> {
        let result = self
            .shared
            .as_ref()
            .and_then(|shared| shared.modified_instances.get(path))
            .map(String::as_str);
        crate::dependencies::observe(
            crate::BindingFact::ModifiedInstance(path.into()),
            crate::FactValue::text(result),
        );
        result
    }
    fn numeric_constant(&self, name: &str) -> Option<u32> {
        let result = self
            .shared
            .as_ref()
            .and_then(|shared| shared.numeric_constants.get(name))
            .copied();
        crate::dependencies::observe(
            crate::BindingFact::NumericConstant(name.into()),
            result.map_or(crate::FactValue::Absent, crate::FactValue::Bits),
        );
        result
    }
    fn string_constant(&self, name: &str) -> Option<&str> {
        let result = self
            .shared
            .as_ref()
            .and_then(|shared| shared.string_constants.get(name))
            .map(String::as_str);
        crate::dependencies::observe(
            crate::BindingFact::StringConstant(name.into()),
            crate::FactValue::text(result),
        );
        result
    }

    /// Replay the exact fact used by lowering against a new frozen declaration
    /// skeleton. This path is shared by disk memo validation and tracked inputs.
    pub fn binding_fact(&self, fact: &crate::BindingFact) -> crate::FactValue {
        use crate::{BindingFact as F, FactValue as V};
        match fact {
            F::Field(n) => V::Boolean(self.has_field_raw(n)),
            F::Global(n) => V::Boolean(self.has_global_raw(n)),
            F::GlobalProc(n) => V::Boolean(self.has_global_proc_raw(n)),
            F::FieldType(n) => V::text(self.field_type_raw(n)),
            F::GlobalType(n) => V::text(self.global_type_raw(n)),
            F::MemberType(o, n) => V::text(self.member_type_raw(o, n)),
            F::MemberGlobal(o, n) => V::text(self.member_global_raw(o, n)),
            F::UniqueMemberGlobal(n) => V::text(self.unique_member_global_raw(n)),
            F::MemberProc(o, n) => V::text(self.member_proc_raw(o, n)),
            F::DeclaredMemberProc(o, n) => V::Boolean(self.has_declared_member_proc_raw(o, n)),
            F::GlobalProcReturnType(n) => V::text(self.global_proc_return_type_raw(n)),
            F::MemberProcReturnType(o, n) => V::text(self.member_proc_return_type_raw(o, n, false)),
            F::ParentProcReturnType(o, n) => V::text(self.member_proc_return_type_raw(o, n, true)),
            F::NumericConstant(n) => self
                .shared
                .as_ref()
                .and_then(|s| s.numeric_constants.get(n))
                .copied()
                .map_or(V::Absent, V::Bits),
            F::StringConstant(n) => V::text(
                self.shared
                    .as_ref()
                    .and_then(|s| s.string_constants.get(n))
                    .map(String::as_str),
            ),
            F::ModifiedInstance(n) => V::text(
                self.shared
                    .as_ref()
                    .and_then(|s| s.modified_instances.get(n))
                    .map(String::as_str),
            ),
            F::SharedPresence => V::Boolean(self.shared.is_some()),
        }
    }

    fn has_field_raw(&self, name: &str) -> bool {
        self.fields.contains(name)
            || (!self.hidden_owner_fields.contains(name)
                && self
                    .owner
                    .as_ref()
                    .is_some_and(|owner| owner.fields.contains(name)))
            || self
                .shared
                .as_ref()
                .is_some_and(|shared| shared.fields.contains(name))
    }

    fn has_global_raw(&self, name: &str) -> bool {
        self.globals.contains(name)
            || self
                .shared
                .as_ref()
                .is_some_and(|shared| shared.globals.contains(name))
    }

    fn has_global_proc_raw(&self, name: &str) -> bool {
        self.global_procs.contains(name)
            || self
                .shared
                .as_ref()
                .is_some_and(|shared| shared.global_procs.contains(name))
    }

    fn field_type_raw(&self, name: &str) -> Option<&str> {
        self.field_types
            .get(name)
            .or_else(|| {
                self.owner
                    .as_ref()
                    .and_then(|owner| owner.field_types.get(name))
            })
            .or_else(|| self.shared.as_ref()?.field_types.get(name))
            .map(String::as_str)
    }

    fn global_type_raw(&self, name: &str) -> Option<&str> {
        self.global_types
            .get(name)
            .or_else(|| self.shared.as_ref()?.global_types.get(name))
            .map(String::as_str)
    }

    fn member_type_raw(&self, owner: &str, name: &str) -> Option<&str> {
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

    fn member_global_raw(&self, owner: &str, name: &str) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        crate::binding_index::member_global(shared, owner, name)
    }

    fn unique_member_global_raw(&self, name: &str) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        if let Some(result) = self.prepared_member_globals.resolve(shared, name) {
            return match result {
                crate::binding_index::MemberGlobalResolution::Unique(symbol) => Some(symbol),
                crate::binding_index::MemberGlobalResolution::Ambiguous
                | crate::binding_index::MemberGlobalResolution::Absent => None,
            };
        }
        if shared.known_member_fields.iter().any(|(owner, members)| {
            members.contains(name) && self.member_global_raw(owner, name).is_none()
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

    fn member_proc_raw(&self, owner: &str, name: &str) -> Option<&str> {
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

    fn has_declared_member_proc_raw(&self, owner: &str, name: &str) -> bool {
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
    fn global_proc_return_type_raw(&self, name: &str) -> Option<&str> {
        self.shared
            .as_ref()?
            .global_proc_return_types
            .get(name)
            .map(String::as_str)
    }
    fn member_proc_return_type_raw(
        &self,
        owner: &str,
        name: &str,
        parent_only: bool,
    ) -> Option<&str> {
        let shared = self.shared.as_ref()?;
        let mut path = shared
            .modified_instances
            .get(owner)
            .map(String::as_str)
            .unwrap_or(owner);
        if parent_only {
            path = shared.parent_types.get(path)?;
        }
        for _ in 0..64 {
            if let Some(return_type) = shared
                .member_proc_return_types
                .get(path)
                .and_then(|members| members.get(name))
            {
                return Some(return_type);
            }
            path = shared.parent_types.get(path)?;
        }
        None
    }
}

#[cfg(test)]
mod owner_binding_tests {
    use super::*;
    use crate::{BindingFact, FactValue};
    #[test]
    fn shared_owner_fields_preserve_static_shadow_and_type_precedence() {
        let owner = Arc::new(OwnerLowerBindings {
            fields: ["value".to_owned(), "static_name".to_owned()]
                .into_iter()
                .collect(),
            field_types: [
                ("value".to_owned(), "/datum/owner".to_owned()),
                ("static_name".to_owned(), "/datum/static".to_owned()),
            ]
            .into_iter()
            .collect(),
        });
        let mut bindings = LowerBindings {
            owner: Some(owner.clone()),
            ..Default::default()
        };
        assert_eq!(
            bindings.binding_fact(&BindingFact::Field("value".into())),
            FactValue::Boolean(true)
        );
        assert_eq!(
            bindings.binding_fact(&BindingFact::FieldType("value".into())),
            FactValue::Text("/datum/owner".into())
        );
        bindings.hide_owner_field("static_name");
        assert_eq!(
            bindings.binding_fact(&BindingFact::Field("static_name".into())),
            FactValue::Boolean(false)
        );
        assert_eq!(
            bindings.binding_fact(&BindingFact::FieldType("static_name".into())),
            FactValue::Text("/datum/static".into())
        );
        bindings
            .field_types
            .insert("value".into(), "/datum/local".into());
        assert_eq!(
            bindings.binding_fact(&BindingFact::FieldType("value".into())),
            FactValue::Text("/datum/local".into())
        );
        let cloned = bindings.clone();
        assert!(Arc::ptr_eq(cloned.owner.as_ref().unwrap(), &owner));
        assert!(owner.fields.contains("static_name"));
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
    crate::dependencies::observe(
        crate::BindingFact::SharedPresence,
        crate::FactValue::Boolean(bindings.shared.is_some()),
    );
    let mut compiler = Compiler {
        result: SimpleProc::default(),
        body_span_base: crate::debug::body_span_base(body),
        current_origin: None,
        bindings,
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
    compiler.parameter_defaults().map_err(|error| vec![error])?;
    let typed = parse_body_items(body);
    if typed.diagnostics.is_empty() && typed_statements_supported(&typed.statements) {
        compiler
            .typed_statements(&typed.statements)
            .map_err(|error| vec![error])?;
    } else {
        compiler.statements(body).map_err(|error| vec![error])?;
    }
    compiler.emit(opcode::END, vec![]);
    compiler.result.local_count = compiler.locals.len() as u32;
    compiler.result.local_names = compiler.locals;
    compiler.result.argument_names = bindings.parameters.clone();
    compiler.result.argument_type_flags = bindings.parameter_type_flags.clone();
    compiler.result.argument_value_sources = bindings.parameter_value_sources.clone();
    if bindings.shared.is_some() {
        compiler
            .result
            .class_paths
            .retain(|path| bindings.modified_instance(path).is_none());
        let mut seen = BTreeSet::new();
        for item in &mut compiler.result.code.items {
            let CodeItem::Instruction(instruction) = item else {
                continue;
            };
            for operand in &mut instruction.operands {
                if let Word::Value(ValueWord::ClassPath { path, .. }) = operand {
                    if bindings.modified_instance(path).is_some() {
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
    body_span_base: usize,
    current_origin: Option<(usize, usize)>,
    bindings: &'a LowerBindings,
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
                    let mut error = error(&statement.raw_header, "invalid or duplicate label");
                    error.statement_origin =
                        crate::debug::relative_span(statement.header_span, self.body_span_base)
                            .map(|(start, end)| crate::debug::RelativeStatementSpan { start, end });
                    return Err(error);
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
        let saved_origin = self.current_origin;
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
            .map_err(|error| self.locate_error(error));
        self.local_slots = saved_slots;
        self.local_types = saved_types;
        self.user_labels = saved_labels;
        self.user_label_iterator_depths = saved_label_iterator_depths;
        self.label_breaks = saved_breaks;
        self.label_loop_depths = saved_depths;
        self.label_iterator_depths = saved_iterator_depths;
        self.current_origin = saved_origin;
        result
    }

    fn typed_statements_inner(&mut self, statements: &[Statement]) -> Result<(), LowerError> {
        for statement in statements {
            self.current_origin =
                crate::debug::relative_span(statement.header_span, self.body_span_base);
            let scoped_statement = matches!(
                &statement.kind,
                StatementKind::For { .. } | StatementKind::Try { .. }
            );
            let saved_slots = scoped_statement.then(|| self.local_slots.clone());
            let saved_types = scoped_statement.then(|| self.local_types.clone());
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
                    self.expression(value, &statement.raw_header)?;
                    self.emit(opcode::POP, vec![]);
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
                        self.local_types.insert(name.into(), format!("/{path}"));
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
                    let path = format!("/{type_name}");
                    let tag = class_tag(&path).ok_or_else(|| {
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
                            self.local_types.insert(name.into(), format!("/{path}"));
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
                            let path = format!("/{type_name}");
                            let tag = class_tag(&path).ok_or_else(|| {
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
                                self.local_types.insert(name.into(), format!("/{path}"));
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
        if let Some((start, end)) = self.current_origin {
            let starts_block = matches!(self.result.code.items.last(), Some(CodeItem::Label(_)));
            if starts_block
                || self
                    .result
                    .statement_origins
                    .last()
                    .is_none_or(|mark| (mark.start, mark.end) != (start, end))
            {
                self.result
                    .statement_origins
                    .push(crate::debug::StatementOrigin {
                        code_item: self.result.code.items.len(),
                        start,
                        end,
                    });
            }
        }
        self.result
            .code
            .items
            .push(CodeItem::Instruction(Instruction { opcode, operands }));
    }

    fn locate_error(&self, mut error: LowerError) -> LowerError {
        if error.statement_origin.is_none() {
            error.statement_origin = self
                .current_origin
                .map(|(start, end)| crate::debug::RelativeStatementSpan { start, end });
        }
        error
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

    fn statements(&mut self, body: &[Item]) -> Result<(), LowerError> {
        let saved_origin = self.current_origin;
        let result = self
            .statements_inner(body)
            .map_err(|error| self.locate_error(error));
        self.current_origin = saved_origin;
        result
    }

    fn statements_inner(&mut self, body: &[Item]) -> Result<(), LowerError> {
        let mut index = 0;
        while index < body.len() {
            let item = &body[index];
            self.current_origin =
                crate::debug::relative_span(item.header_span, self.body_span_base);
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
                    self.current_origin =
                        crate::debug::relative_span(clause.header_span, self.body_span_base);
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
        self.expression(expr, statement)?;
        self.emit(opcode::POP, vec![]);
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
                .inferred_expression_type(object)
                .and_then(|owner| self.bindings.member_global(&owner, selector))
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
            if let Some(path) = self.inferred_expression_type(target) {
                let declaration = format!("var{path}/__value");
                self.local_initializer(value, &declaration, statement)?;
            } else {
                self.expression(value, statement)?;
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
        match name {
            "src" => Ok(VariableWord::Src),
            "usr" => Ok(VariableWord::Usr),
            "world" => Ok(VariableWord::World),
            "args" => Ok(VariableWord::Args),
            "caller" => Ok(VariableWord::Caller),
            "callee" => Ok(VariableWord::Callee),
            "." => Ok(VariableWord::Dot),
            _ if self.bindings.has_field(name) => {
                self.intern_string(name);
                Ok(VariableWord::SetCache(
                    Box::new(VariableWord::Src),
                    Box::new(VariableWord::Field(name.to_owned())),
                ))
            }
            _ if self.bindings.has_global(name) => Ok(VariableWord::Global(name.to_owned())),
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
                object, selector, ..
            } => {
                if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                    if selector == "vars" {
                        return Ok(VariableWord::Global(BUILTIN_GLOBAL_VARS_SYMBOL.into()));
                    }
                    if self.bindings.has_global(selector) {
                        return Ok(VariableWord::Global(selector.clone()));
                    }
                    return Err(error(
                        statement,
                        &format!("unresolved global variable: {selector}"),
                    ));
                }
                if let Some(owner) = self.inferred_expression_type(object) {
                    if let Some(symbol) = self.bindings.member_global(&owner, selector) {
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
            Ok(variable) => Ok(variable),
            Err(_) => {
                let ExprKind::Member {
                    object, selector, ..
                } = &target.kind
                else {
                    return Err(error(statement, "unsupported assignment target"));
                };
                self.expression(object, statement)?;
                self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                if let Some(symbol) = self.bindings.unique_member_global(selector) {
                    return Ok(VariableWord::Global(symbol.to_owned()));
                }
                self.intern_string(selector);
                Ok(VariableWord::Field(selector.clone()))
            }
        }
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
        self.emit(opcode, vec![Word::Variable(variable)]);
        Ok(())
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
            let path = format!("/{type_name}");
            let tag = class_tag(&path)
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
                let path = format!("/{type_name}");
                let tag = class_tag(&path)
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
            let path = format!("/{type_name}");
            let tag = class_tag(&path)
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

    fn inferred_expression_type(&self, expr: &Expr) -> Option<String> {
        let inferred = match &expr.kind {
            ExprKind::TypePath(path) => Some(path.clone()),
            ExprKind::Ident(name) => {
                if name == "src" {
                    return self.bindings.current_type_path.clone();
                }
                if name == "usr" {
                    return Some("/mob".into());
                }
                if matches!(name.as_str(), "callee" | "caller")
                    && !self.local_slots.contains_key(name)
                    && !self
                        .bindings
                        .parameters
                        .iter()
                        .any(|parameter| parameter == name)
                {
                    return Some("/callee".into());
                }
                self.local_types
                    .get(name)
                    .map(String::as_str)
                    .or_else(|| self.bindings.parameter_types.get(name).map(String::as_str))
                    .or_else(|| self.bindings.field_type(name))
                    .or_else(|| self.bindings.global_type(name))
                    .map(str::to_owned)
            }
            ExprKind::Group(inner) => self.inferred_expression_type(inner),
            ExprKind::Member {
                object, selector, ..
            } => {
                if matches!(&object.kind, ExprKind::Ident(name) if name == "global") {
                    return self.bindings.global_type(selector).map(str::to_owned);
                }
                if matches!(&object.kind, ExprKind::Ident(name) if name == "src") {
                    return self.bindings.field_type(selector).map(str::to_owned);
                }
                let owner = self.inferred_expression_type(object)?;
                self.bindings
                    .member_type(&owner, selector)
                    .map(str::to_owned)
            }
            ExprKind::SafeMember { object, selector } => {
                let owner = self.inferred_expression_type(object)?;
                self.bindings
                    .member_type(&owner, selector)
                    .map(str::to_owned)
            }
            ExprKind::Call { callee, .. } => self.inferred_call_type(callee),
            _ => None,
        };
        inferred.map(|path| {
            self.bindings
                .modified_instance(&path)
                .map(str::to_owned)
                .unwrap_or(path)
        })
    }

    fn inferred_call_type(&self, callee: &Expr) -> Option<String> {
        match &callee.kind {
            ExprKind::Ident(name) if name == ".." => {
                let owner = self.bindings.current_type_path.as_deref()?;
                let name = self
                    .bindings
                    .current_proc_path
                    .as_deref()?
                    .rsplit('/')
                    .next()?;
                self.bindings
                    .parent_proc_return_type(owner, name)
                    .map(str::to_owned)
            }
            ExprKind::Ident(name) => {
                // Bare builtin calls take precedence over authored procedures
                // in emission. Their results cannot inherit a source signature.
                if crate::builtin_catalog::lookup(name).is_some()
                    || matches!(
                        name.as_str(),
                        "new"
                            | "list"
                            | "sound"
                            | "image"
                            | "icon"
                            | "regex"
                            | "matrix"
                            | "input"
                            | "locate"
                            | "initial"
                            | "issaved"
                            | "istype"
                            | "pick"
                            | "call"
                            | "arglist"
                            | "text"
                            | "CRASH"
                    )
                {
                    return None;
                }
                let member = self.bindings.current_type_path.as_deref().filter(|owner| {
                    self.bindings.has_declared_member_proc(owner, name)
                        || self.bindings.member_proc(owner, name).is_some()
                });
                if let Some(owner) = member {
                    self.bindings
                        .member_proc_return_type(owner, name)
                        .map(str::to_owned)
                } else if self.bindings.has_global_proc(name) {
                    self.bindings
                        .global_proc_return_type(name)
                        .map(str::to_owned)
                } else {
                    None
                }
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember { object, selector } => {
                let owner = self.inferred_expression_type(object)?;
                self.bindings
                    .member_proc_return_type(&owner, selector)
                    .map(str::to_owned)
            }
            ExprKind::Group(inner) => self.inferred_call_type(inner),
            _ => None,
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
            ExprKind::ObjectInitializer { .. } => {
                return Err(error(
                    statement,
                    "object initializer requires an anonymous class entry",
                ));
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
                    if self.seen_resources.insert(path.into()) {
                        self.result.resources.push(path.into());
                    }
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::Resource(path.into()))],
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
                    self.emit(
                        opcode::PUSH_VAL,
                        vec![Word::Value(ValueWord::ProcPath(path.clone()))],
                    );
                    return Ok(());
                }
                let tag = class_tag(path)
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
                if name == "null" || name == "FALSE" || name == "TRUE" {
                    let literal = Expr {
                        kind: ExprKind::Literal(name.clone()),
                        span: expr.span,
                    };
                    return self.expression(&literal, statement);
                }
                if !self.local_slots.contains_key(name)
                    && !self
                        .bindings
                        .parameters
                        .iter()
                        .any(|parameter| parameter == name)
                    && !self.bindings.has_field(name)
                    && !self.bindings.has_global(name)
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
                            let tag = class_tag(&path).ok_or_else(|| {
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
                    if let Some(bits) = self.bindings.numeric_constant(name) {
                        let number = f32::from_bits(bits);
                        if number >= 0.0 && number <= u16::MAX as f32 && number.fract() == 0.0 {
                            self.emit(opcode::PUSH_INT, vec![Word::Immediate(number as u32)]);
                        } else {
                            self.emit(opcode::PUSH_VAL, vec![Word::Value(ValueWord::Number(bits))]);
                        }
                        return Ok(());
                    }
                    if let Some(value) = self.bindings.string_constant(name).map(str::to_owned) {
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
                        if let Some(symbol) = self.bindings.unique_member_global(selector) {
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
            ExprKind::SafeMember { .. } => {
                // A chain restores each intermediate receiver on the way out.
                // Each null branch skips only cache frames that were pushed:
                // the innermost target precedes its enclosing PopCache.
                let mut chain = Vec::new();
                let mut receiver = expr;
                while let ExprKind::SafeMember { object, selector } = &receiver.kind {
                    chain.push((object.as_ref(), selector));
                    receiver = object;
                }
                chain.reverse();
                self.expression(receiver, statement)?;
                let mut ends = Vec::with_capacity(chain.len());
                for (index, (object, selector)) in chain.iter().enumerate() {
                    let end = self.label();
                    self.emit(317, vec![Word::Branch(end.clone())]);
                    if index + 1 < chain.len() {
                        self.emit(opcode::PUSH_CACHE, vec![]);
                    }
                    let variable = self
                        .inferred_expression_type(object)
                        .and_then(|owner| self.bindings.member_global(&owner, selector))
                        .map(|symbol| VariableWord::Global(symbol.to_owned()))
                        .unwrap_or_else(|| VariableWord::Field((*selector).clone()));
                    if matches!(variable, VariableWord::Field(_)) {
                        self.intern_string(selector);
                    }
                    self.emit(opcode::GET_VAR, vec![Word::Variable(variable)]);
                    ends.push(end);
                }
                for (index, end) in ends.into_iter().rev().enumerate() {
                    if index != 0 {
                        self.emit(opcode::POP_CACHE, vec![]);
                    }
                    self.result.code.items.push(CodeItem::Label(end));
                }
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
                                let proc_selector = if let ExprKind::Call { callee, .. } =
                                    &object.kind
                                {
                                    if let ExprKind::TypePath(path) = &callee.kind {
                                        self.bindings.member_proc(path, selector).map(str::to_owned)
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
                        .inferred_expression_type(object)
                        .and_then(|owner| {
                            self.bindings
                                .member_proc(&owner, selector)
                                .map(str::to_owned)
                        })
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
                        if !self.bindings.has_global_proc(selector) {
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
                        .inferred_expression_type(object)
                        .and_then(|owner| {
                            self.bindings
                                .member_proc(&owner, selector)
                                .map(str::to_owned)
                        })
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
                            opcode::CALL,
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
                    if matches!(target.kind, ExprKind::StaticMember { .. }) {
                        // `::` already reads the receiver's initial field. The
                        // receiver is evaluated once, including type values and
                        // computed receivers; another Initial modifier is wrong.
                        return self.expression(target, statement);
                    }
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
                    let (owner, selector) = match &target.kind {
                        ExprKind::Ident(field) if self.bindings.has_field(field) => {
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
                    if let ExprKind::StaticMember { object, selector } = &target.kind {
                        self.expression(object, statement)?;
                        let safe_labels = self.defer_safe_postfix_labels(object);
                        self.emit(opcode::SET_VAR, vec![Word::Variable(VariableWord::Cache)]);
                        self.intern_string(selector);
                        self.emit(
                            opcode::GET_VAR,
                            vec![Word::Variable(VariableWord::IsSaved(Box::new(
                                VariableWord::Field(selector.clone()),
                            )))],
                        );
                        self.result.code.items.extend(safe_labels);
                        return Ok(());
                    }
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
                        [value] => {
                            let mut target = value;
                            while let ExprKind::Group(inner) = &target.kind {
                                target = inner;
                            }
                            // Native accepts members selected through a typed
                            // result, but a call itself has no one-arg istype form.
                            if matches!(&target.kind, ExprKind::Call { .. }) {
                                None
                            } else {
                                self.inferred_expression_type(value)
                            }
                        }
                        _ => {
                            return Err(error(statement, "istype() requires one or two arguments"))
                        }
                    }
                    .ok_or_else(|| error(statement, "istype() cannot infer a declared type"))?;
                    self.expression(&args[0], statement)?;
                    let tag = class_tag(&target_type)
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
                let has_member_proc =
                    self.bindings
                        .current_type_path
                        .as_deref()
                        .is_some_and(|owner| {
                            self.bindings.has_declared_member_proc(owner, name)
                                || self.bindings.member_proc(owner, name).is_some()
                        });
                if self.bindings.has_global_proc(name) && !has_member_proc {
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
                        .bindings
                        .current_type_path
                        .as_deref()
                        .and_then(|owner| self.bindings.member_proc(owner, name).map(str::to_owned))
                        .map(member_proc_selector)
                        .unwrap_or_else(|| VariableWord::DynamicProc(name.replace('_', " ")));
                    if self.bindings.shared.is_some()
                        && matches!(proc_selector, VariableWord::DynamicProc(_))
                        && !self
                            .bindings
                            .current_type_path
                            .as_deref()
                            .is_some_and(|owner| {
                                self.bindings.has_declared_member_proc(owner, name)
                            })
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
                        opcode::CALL,
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
        statement_origin: None,
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
mod tests {
    use super::*;
    use crate::{link_proc, Ledger, Table};

    #[test]
    fn nameof_fields_and_variables_match_native_without_evaluating_receivers() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/nameof_references.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/nameof_references.dm"
        ));
        let body = &ast.items[0]
            .children
            .iter()
            .find(|item| item.header == "proc/reference_names()")
            .unwrap()
            .children;
        let compiled = compile_simple_proc(body).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/datum/nameof_member/proc/reference_names")
            })
            .unwrap();
        assert_eq!(
            link_proc(&compiled.code, &ledger).unwrap().words,
            native.proc_code_words(id).unwrap()
        );
        for (source, expected) in [
            ("type::name", "name"),
            ("type::vv_VAS", "vv_VAS"),
            ("(type::name)", "name"),
            ("receiver().name", "name"),
        ] {
            assert_eq!(
                nameof_reference(&parse_expression(source).expr.unwrap()),
                Some(expected)
            );
        }
        let ast = dm_syntax::parse("/proc/test()\n    return nameof(type::vv_VAS)\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.strings, ["vv_VAS"]);
        assert!(compiled.class_paths.is_empty());
    }

    #[test]
    fn initial_and_issaved_static_members_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/initial_static_member/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/initial_static_member/probe.native.bin"
        ))
        .unwrap();
        for name in [
            "read_path",
            "read_child",
            "read_value",
            "read_side_effect",
            "saved_path",
        ] {
            let path = format!("/proc/{name}");
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(&format!("{path}(")))
                .unwrap();
            let bindings = LowerBindings {
                parameters: if name == "read_value" {
                    vec!["value".into()]
                } else {
                    vec![]
                },
                global_procs: BTreeSet::from(["make_value".into()]),
                ..Default::default()
            };
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            for key in &compiled.class_paths {
                let id = native
                    .classes
                    .iter()
                    .position(|class| native.string(class.path_string_id()) == Some(key.as_bytes()))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::Class, key), id as u32)
                    .unwrap();
            }
            let helper = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/make_value"))
                .unwrap();
            ledger
                .bind(
                    crate::Symbol::new(Table::Proc, "/proc/make_value"),
                    helper as u32,
                )
                .unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(
                link_proc(&compiled.code, &ledger).unwrap().words,
                native.proc_code_words(id).unwrap(),
                "{path}"
            );
        }
    }

    #[test]
    fn shifts_fold_native_unsigned_24_bit_values_and_leave_unsafe_cases_to_runtime() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/integer_shifts.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/integer_shifts.dm"
        ));
        for id in 0..4 {
            let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
            assert_eq!(
                link_proc(&compiled.code, &Ledger::default()).unwrap().words,
                native.proc_code_words(id).unwrap()
            );
        }
        for source in [
            "1 << 32",
            "1 << -1",
            "1 >> 32",
            "1 >> -1",
            "1.#INF << 1",
            "2147483648 >> 1",
            "-2147483904 << 1",
            "5.5 >> 1",
            "1 << 1.5",
        ] {
            assert!(
                fold_number(&parse_expression(source).expr.unwrap()).is_none(),
                "{source}"
            );
        }
    }

    #[test]
    fn modulo_constant_folding_truncates_operands_like_native() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/integer_modulo.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/integer_modulo.dm"
        ));
        for id in 0..3 {
            let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
            assert_eq!(
                link_proc(&compiled.code, &Ledger::default()).unwrap().words,
                native.proc_code_words(id).unwrap()
            );
        }
        for source in [
            "5 % 0.5",
            "-2147483648 % -1",
            "1.#INF % 2",
            "2147483648 % 2",
        ] {
            assert!(
                fold_number(&parse_expression(source).expr.unwrap()).is_none(),
                "{source}"
            );
        }
    }

    #[test]
    fn global_vars_builtin_does_not_alias_ordinary_vars_declarations() {
        let ast = dm_syntax::parse("/proc/test()\n    return vars + length(global.vars)\n");
        let bindings = LowerBindings {
            globals: BTreeSet::from(["vars".into()]),
            ..Default::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let mut references = Vec::new();
        compiled
            .code
            .for_each_reference(|table, key| references.push((table, key.to_owned())));
        assert_eq!(
            references,
            [
                (Table::Variable, "vars".into()),
                (Table::Variable, BUILTIN_GLOBAL_VARS_SYMBOL.into())
            ]
        );
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Variable, "vars"), 10)
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::Variable, BUILTIN_GLOBAL_VARS_SYMBOL),
                177,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert!(linked
            .words
            .windows(3)
            .any(|words| words == [opcode::GET_VAR, 0xffdb, 10]));
        assert!(linked
            .words
            .windows(3)
            .any(|words| words == [opcode::GET_VAR, 0xffdb, 177]));
    }

    #[test]
    fn initial_globals_locals_and_parameters_match_native() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/global_initial.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/global_initial.dm"
        ));
        for name in [
            "initial_global",
            "initial_global_qualified",
            "saved_global",
            "initial_local",
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
                .unwrap();
            let bindings = LowerBindings {
                globals: BTreeSet::from(["initial_probe".into()]),
                parameters: if name == "initial_local" {
                    vec!["value".into()]
                } else {
                    vec![]
                },
                fields: if name == "initial_local" {
                    BTreeSet::from(["local".into(), "value".into()])
                } else {
                    BTreeSet::new()
                },
                ..Default::default()
            };
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            let id = native
                .variables
                .iter()
                .position(|variable| native.string(variable.name) == Some(b"initial_probe"))
                .unwrap();
            ledger
                .bind(
                    crate::Symbol::new(Table::Variable, "initial_probe"),
                    id as u32,
                )
                .unwrap();
            let path = format!("/proc/{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(
                link_proc(&compiled.code, &ledger).unwrap().words,
                native.proc_code_words(id).unwrap()
            );
        }
    }

    #[test]
    fn default_arguments_and_mutated_iteration_match_native() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/control_runtime.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/control_runtime.dm"
        ));
        for (name, params, defaults) in [
            (
                "control_defaults",
                vec!["a".into(), "b".into(), "c".into()],
                vec![Some("3".into()), Some("4".into()), Some("5".into())],
            ),
            ("control_iteration", vec![], vec![]),
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
                .unwrap();
            let bindings = LowerBindings {
                parameters: params,
                parameter_defaults: defaults,
                global_procs: BTreeSet::from(["control_defaults".into()]),
                ..Default::default()
            };
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let helper = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/control_defaults"))
                .unwrap();
            ledger
                .bind(
                    crate::Symbol::new(Table::Proc, "/proc/control_defaults"),
                    helper as u32,
                )
                .unwrap();
            let path = format!("/proc/{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
        }
    }

    #[test]
    fn short_circuit_index_assignments_preserve_receiver_cache_like_native() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/short_assignment.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/short_assignment.dm"
        ));
        for id in 0..3 {
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &["a".into(), "b".into()])
                    .unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
        for (name, params) in [
            ("short_assignment_member", vec!["a".into(), "b".into()]),
            (
                "short_assignment_index_effects",
                vec!["a".into(), "b".into(), "count".into()],
            ),
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
                .unwrap();
            let bindings = LowerBindings {
                parameters: params,
                global_procs: BTreeSet::from([
                    "assignment_receiver".into(),
                    "assignment_index".into(),
                ]),
                ..Default::default()
            };
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            for helper in ["assignment_receiver", "assignment_index"] {
                let path = format!("/proc/{helper}");
                let id = native
                    .procs
                    .iter()
                    .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::Proc, path), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let path = format!("/proc/{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn procedure_and_verb_namespaces_are_native_strings() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/proc_namespace.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/proc_namespace.dm"
        ));
        for (name, namespace) in [
            ("proc_group", "proc"),
            ("verb_group", "verb"),
            ("proc_types", "proc"),
            ("verb_types", "verb"),
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header == format!("/proc/{name}()"))
                .unwrap();
            let compiled = compile_simple_proc(&item.children).unwrap();
            assert!(compiled.class_paths.is_empty());
            let path = format!("/datum/namespace_probe/{namespace}");
            let string = native
                .strings
                .iter()
                .position(|entry| entry.data == path.as_bytes())
                .unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::String, path), string as u32)
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let proc = native
                .procs
                .iter()
                .position(|proc| {
                    native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
                })
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(proc).unwrap());
        }
    }

    #[test]
    fn procedure_and_verb_constructors_use_native_proc_references() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/proc_namespace.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/proc_namespace.dm"
        ));
        for (name, target, id) in [
            ("new_verb", "/datum/namespace_probe/verb/third", 2),
            ("new_proc", "/datum/namespace_probe/proc/first", 0),
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header == format!("/proc/{name}()"))
                .unwrap();
            let compiled = compile_simple_proc(&item.children).unwrap();
            assert!(compiled.class_paths.is_empty());
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Proc, target), id)
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let proc = native
                .procs
                .iter()
                .position(|proc| {
                    native.string(proc.strings[0]) == Some(format!("/proc/{name}").as_bytes())
                })
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(proc).unwrap());
        }
    }

    #[test]
    fn modified_types_link_as_native_instances_in_literals_and_constructors() {
        let alias = "/datum/example/__dm_modified_123";
        let mut shared = SharedLowerBindings::default();
        shared
            .modified_instances
            .insert(alias.into(), "/datum/example".into());
        let bindings = LowerBindings {
            shared: Some(Arc::new(shared)),
            ..Default::default()
        };
        let ast = dm_syntax::parse(&format!(
            "/proc/example()\n    var/a = {alias}\n    return new {alias}()\n"
        ));
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        assert!(compiled.class_paths.is_empty());
        assert_eq!(compiled.instance_paths, [alias]);
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Instance, alias), 0x123456)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked
                .words
                .windows(2)
                .filter(|words| *words == [41 | (0x12 << 8), 0x3456])
                .count(),
            2
        );
        let mut references = Vec::new();
        compiled
            .code
            .for_each_reference(|table, key| references.push((table, key.to_owned())));
        assert_eq!(
            references,
            vec![
                (Table::Instance, alias.into()),
                (Table::Instance, alias.into())
            ]
        );
    }

    #[test]
    fn mixed_associative_list_matches_native() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/assoc_nativekeys.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse("/proc/a_mixed(x)\n    return list(x,\"key\"=2,x+1)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/a_mixed".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
    }

    #[test]
    fn parent_call_matches_native_inherited_proc() {
        let ast = dm_syntax::parse("/datum/child/result()\n    return ..() + 1\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inheritance.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(b"/fixture_child/result"))
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn parent_call_with_explicit_arguments_uses_native_call_parent_args() {
        let ast = dm_syntax::parse(
            "/datum/child/Initialize(mapload, amount)\n    return ..(mapload, amount + 1)\n",
        );
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["mapload".into(), "amount".into()],
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let call = decoded
            .iter()
            .find(|instruction| instruction.opcode == 0x2d)
            .unwrap();
        assert_eq!(call.operands, vec![2]);
    }

    #[test]
    fn implicit_parent_forwarding_and_explicit_empty_arguments_match_native() {
        let source = include_str!("../../../fixtures/native_compiler/parent_forwarding.dm");
        let ast = dm_syntax::parse(source);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/parent_forwarding.native.bin"
        ))
        .unwrap();
        for (owner, method, params) in [
            ("/datum/forwarding/child", "single", vec!["value".into()]),
            (
                "/datum/forwarding/child",
                "multiple",
                vec!["a".into(), "b".into()],
            ),
            ("/datum/forwarding/empty", "single", vec!["value".into()]),
        ] {
            let item = ast.items.iter().find(|item| item.header == owner).unwrap();
            let body = &item
                .children
                .iter()
                .find(|item| item.header.starts_with(&format!("{method}(")))
                .unwrap()
                .children;
            let compiled = compile_simple_proc_with_params(body, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let path = format!("{owner}/{method}");
            let proc_id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(proc_id).unwrap(),
                "{path}"
            );
        }
    }

    #[test]
    fn parent_arglist_matches_native_fixture() {
        let ast = dm_syntax::parse("/proc/arglist_root_super(list/L)\n    return ..(arglist(L))\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/arglist_builtin_forms.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/arglist_root_super".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn self_arglist_matches_native_fixture() {
        let ast = dm_syntax::parse("/proc/arglist_self(list/L)\n    return .(arglist(L))\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/arglist_builtin_forms.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/arglist_self".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn rand_two_arguments_uses_native_builtin_opcode() {
        let ast = dm_syntax::parse("/proc/test()\n    return rand(1, 2) == null\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/null_equality_ownership/probe.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/global_equal_null".as_slice())
            })
            .unwrap();
        let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(ours[2].opcode, 0x23);
        assert!(
            theirs.iter().any(|instruction| instruction.opcode == 0x23),
            "{theirs:?}"
        );
    }

    #[test]
    fn isnull_call_uses_native_builtin_opcode() {
        let ast = dm_syntax::parse("/proc/test()\n    return isnull(rand(1, 2))\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/null_equality_ownership/probe.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/builtin_null".as_slice())
            })
            .unwrap();
        let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert!(ours
            .iter()
            .any(|instruction| instruction.opcode == opcode::IS_NULL));
        assert!(theirs
            .iter()
            .any(|instruction| instruction.opcode == opcode::IS_NULL));
    }

    #[test]
    fn ceil_matches_native_builtin_fixture() {
        let ast = dm_syntax::parse("/proc/b_ceiling(x)\n    return ceil(x)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/builtin_next.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/b_ceiling".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn clamp_emits_builtin_after_three_values() {
        let ast = dm_syntax::parse("/proc/test(x)\n    return clamp(x, 0, 100)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let code = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(code[3].opcode, 0x14a);
    }

    #[test]
    fn min_max_match_native_single_and_pair_fixtures() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/min_max_single/min_max_single.native.bin"
        ))
        .unwrap();
        for (name, params, body) in [
            ("min_single", vec!["value"], "return min(value)"),
            ("max_single", vec!["value"], "return max(value)"),
            ("min_pair", vec!["a", "b"], "return min(a,b)"),
            ("max_pair", vec!["a", "b"], "return max(a,b)"),
        ] {
            let source = format!("/proc/{name}()\n    {body}\n");
            let ast = dm_syntax::parse(&source);
            let compiled = compile_simple_proc_with_params(
                &ast.items[0].children,
                &params.into_iter().map(str::to_owned).collect::<Vec<_>>(),
            )
            .unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let path = format!("/proc/{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
        }
    }

    #[test]
    fn min_max_arglist_match_native_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/builtin_final.native.bin"
        ))
        .unwrap();
        for (name, body) in [
            ("bf_maxlist", "return max(arglist(L))"),
            ("bf_minlist", "return min(arglist(L))"),
        ] {
            let source = format!("/proc/{name}(L)\n    {body}\n");
            let ast = dm_syntax::parse(&source);
            let compiled =
                compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let path = format!("/proc/{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
        }
    }

    #[test]
    fn floor_matches_native_builtin_fixture() {
        let ast = dm_syntax::parse("/proc/b_floor(x)\n    return floor(x)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/builtin_next.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/b_floor".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn raw_unicode_string_matches_native_fixture() {
        let ast = dm_syntax::parse("/proc/literal_raw()\n    return @\"Ａ２～\"\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/literal_format_unicode/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        let string_id = native
            .strings
            .iter()
            .position(|string| string.data == "Ａ２～".as_bytes())
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::String, "Ａ２～"),
                string_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/literal_raw".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn length_matches_native_fixture() {
        let ast = dm_syntax::parse("/proc/literal_length()\n    return length(\"Ａ２～\")\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/literal_format_unicode/probe.native.bin"
        ))
        .unwrap();
        let string_id = native
            .strings
            .iter()
            .position(|string| string.data == "Ａ２～".as_bytes())
            .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::String, "Ａ２～"),
                string_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/literal_length".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn copytext_three_arguments_matches_native_fixture() {
        let ast =
            dm_syntax::parse("/proc/literal_copytext()\n    return copytext(\"Ａ２～\", 1, 4)\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/literal_format_unicode/probe.native.bin"
        ))
        .unwrap();
        let string_id = native
            .strings
            .iter()
            .position(|string| string.data == "Ａ２～".as_bytes())
            .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::String, "Ａ２～"),
                string_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/literal_copytext".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn copytext_two_arguments_pads_native_null_end() {
        let ast = dm_syntax::parse("/proc/test(x)\n    return copytext(x, 2)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let code = byond_dmb::bytecode::decode(
            &link_proc(&compiled.code, &Ledger::default()).unwrap().words,
        )
        .unwrap();
        assert_eq!(code[2].opcode, opcode::PUSH_VAL);
        assert_eq!(code[2].operands, vec![0, 0]);
        assert_eq!(code[3].opcode, 0x6e);
    }

    #[test]
    fn text2num_uses_native_builtin_opcode() {
        let ast = dm_syntax::parse("/proc/test(x)\n    return text2num(x)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let ours = byond_dmb::bytecode::decode(
            &link_proc(&compiled.code, &Ledger::default()).unwrap().words,
        )
        .unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/cable_numeric_parse/probe.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/obj/cable/proc/parse".as_slice())
            })
            .unwrap();
        let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(ours[1].opcode, 0x76);
        assert!(theirs.iter().any(|instruction| instruction.opcode == 0x76));
    }

    #[test]
    fn findtext_two_arguments_uses_native_defaults() {
        let ast = dm_syntax::parse("/proc/test(x)\n    return findtext(x, \"-\")\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "-"), 1)
            .unwrap();
        let ours = byond_dmb::bytecode::decode(&link_proc(&compiled.code, &ledger).unwrap().words)
            .unwrap();
        assert_eq!(ours[2].opcode, opcode::PUSH_INT);
        assert_eq!(ours[2].operands, vec![1]);
        assert_eq!(ours[3].opcode, opcode::PUSH_VAL);
        assert_eq!(ours[3].operands, vec![0, 0]);
        assert_eq!(ours[4].opcode, 0x6f);
    }

    #[test]
    fn del_world_matches_native_fixture() {
        let ast =
            dm_syntax::parse("/obj/proc/delete_intrinsic_world()\n    del(world)\n    return 7\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/delete_readonly_intrinsics/probe.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0])
                    == Some(b"/obj/proc/delete_intrinsic_world".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn implicit_field_reads_from_src_like_native() {
        let ast = dm_syntax::parse("/datum/cache_binding/proc/read(arg)\n    return value\n");
        let mut bindings = LowerBindings::default();
        bindings.parameters.push("arg".into());
        bindings.fields.insert("value".into());
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/cache_binding_freeze/probe.native.bin"
        ))
        .unwrap();
        let field_id = native
            .strings
            .iter()
            .position(|string| string.data == b"value")
            .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "value"), field_id as u32)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/datum/cache_binding/proc/read".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn implicit_field_write_matches_native_src_receiver() {
        let ast = dm_syntax::parse(
            "/datum/holder/proc/setter_reads()\n    value = 9\n    return value + other\n",
        );
        let mut bindings = LowerBindings::default();
        bindings.fields.extend(["value".into(), "other".into()]);
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/setter_cache_boundaries/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for name in ["value", "other"] {
            let id = native
                .strings
                .iter()
                .position(|string| string.data == name.as_bytes())
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, name), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0])
                    == Some(b"/datum/holder/proc/setter_reads".as_slice())
            })
            .unwrap();
        let native_words = native.proc_code_words(id).unwrap();
        assert_eq!(&linked.words[..6], &native_words[..6]);
        // DreamMaker reuses its cached src binding after this setter. We
        // explicitly bind src again for later field reads.
    }

    #[test]
    fn world_log_output_matches_native_instruction_sequence() {
        let ast = dm_syntax::parse("/world/New()\n    world.log << \"MAPPED cable\"\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/cable_numeric_parse/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        let log_id = native
            .strings
            .iter()
            .position(|string| string.data == b"log")
            .unwrap();
        let message_id = native
            .strings
            .iter()
            .position(|string| string.data == b"MAPPED cable")
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::String, "log"), log_id as u32)
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::String, "MAPPED cable"),
                message_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/world/New".as_slice()))
            .unwrap();
        assert_eq!(
            &linked.words[..8],
            &native.proc_code_words(id).unwrap()[27..35]
        );
    }

    #[test]
    fn round_to_multiple_uses_native_opcode() {
        let ast = dm_syntax::parse("/proc/test(x)\n    return round(x, 0.001)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let mut ledger = Ledger::default();
        for value in &compiled.strings {
            ledger
                .bind(crate::Symbol::new(Table::String, value), 1)
                .unwrap();
        }
        let ours = byond_dmb::bytecode::decode(&link_proc(&compiled.code, &ledger).unwrap().words)
            .unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/indexed_conditional.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/ic_round".as_slice()))
            .unwrap();
        let theirs = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert!(ours.iter().any(|instruction| instruction.opcode == 0x44));
        assert!(theirs.iter().any(|instruction| instruction.opcode == 0x44));
    }

    #[test]
    fn regex_calls_match_native_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/call_overloads.native.bin"
        ))
        .unwrap();
        for (name, params, body) in [
            ("o_regex", vec!["t", "f"], "return regex(t,f)"),
            ("o_regex_one", vec!["t"], "return regex(t)"),
            ("o_regex_quote", vec!["t"], "return regex(t,1)"),
        ] {
            let source = format!("/proc/{name}()\n    {body}\n");
            let ast = dm_syntax::parse(&source);
            let compiled = compile_simple_proc_with_params(
                &ast.items[0].children,
                &params.into_iter().map(str::to_owned).collect::<Vec<_>>(),
            )
            .unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let path = format!("/proc/{name}");
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
        }
        let raw = dm_syntax::parse("/proc/test()\n    return regex(@\"^\\w+$\", \"g\")\n");
        let compiled = compile_simple_proc(&raw.items[0].children).unwrap();
        assert!(compiled.strings.iter().any(|value| value == "^\\w+$"));
    }

    #[test]
    fn unsupported_initial_reference_fails_closed() {
        let ast = dm_syntax::parse("/obj/proc/test()\n    return initial(icon)\n");
        let errors = compile_simple_proc(&ast.items[0].children).unwrap_err();
        assert!(errors[0].reason.contains("field reference"));
    }

    #[test]
    fn invalid_builtin_argument_count_fails_closed() {
        for (source, expected) in [(
            "/proc/test()\n    return alert()\n",
            "alert() requires one to six arguments",
        )] {
            let ast = dm_syntax::parse(source);
            let errors = compile_simple_proc(&ast.items[0].children).unwrap_err();
            assert!(errors[0].reason.contains(expected), "{errors:?}");
        }
    }

    #[test]
    fn safe_navigation_uses_native_cache_guards() {
        let ast = dm_syntax::parse(
            "/proc/test(a, key)\n    return a?[key.value]\n/proc/member(a)\n    return a?.value\n/proc/safe_call(a, b)\n    return a?.f(b)\n",
        );
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        for (item, params, expected) in [
            (
                &ast.items[0],
                vec!["a".into(), "key".into()],
                vec![
                    opcode::GET_VAR,
                    317,
                    opcode::PUSH_CACHE,
                    opcode::GET_VAR,
                    opcode::GET_VAR,
                    opcode::LIST_GET,
                    opcode::POP_CACHE,
                ],
            ),
            (
                &ast.items[1],
                vec!["a".into()],
                vec![opcode::GET_VAR, 317, opcode::GET_VAR],
            ),
            (
                &ast.items[2],
                vec!["a".into(), "b".into()],
                vec![
                    opcode::GET_VAR,
                    317,
                    opcode::PUSH_CACHE,
                    opcode::GET_VAR,
                    opcode::POP_CACHE,
                    opcode::CALL,
                ],
            ),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
            let opcodes: Vec<_> = decoded
                .iter()
                .map(|instruction| instruction.opcode)
                .collect();
            assert_eq!(&opcodes[..expected.len()], expected);
            let guard = &decoded[1];
            assert_eq!(
                guard.branch_targets().unwrap(),
                vec![decoded[expected.len()].offset as u32]
            );
        }
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/safe_index.native.bin"
        ))
        .unwrap();
        for path in [
            b"/proc/safe_computed_index".as_slice(),
            b"/proc/safe_nested_index",
        ] {
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path))
                .unwrap();
            let decoded = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            assert_eq!(decoded[1].opcode, 317);
            assert_eq!(decoded[2].opcode, opcode::PUSH_CACHE);
        }
    }

    #[test]
    fn runtime_power_matches_native_fixture() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/runtime_power/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()])
                .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/runtime_power/probe.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/power".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn safe_index_assignment_matches_native_fixture() {
        let ast = dm_syntax::parse("/proc/safe_index_assign(list/a,b,c)\n    a?[b] = c\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["a".into(), "b".into(), "c".into()],
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/safe_index.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/safe_index_assign".as_slice())
            })
            .unwrap();
        let native_words = native.proc_code_words(id).unwrap();
        assert_eq!(
            linked.words[..native_words.len() - 1],
            native_words[..native_words.len() - 1]
        );
    }

    #[test]
    fn safe_index_augmented_assignment_matches_native_fixture() {
        let ast = dm_syntax::parse("/proc/safe_index_add(list/a,b,c)\n    a?[b] += c\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["a".into(), "b".into(), "c".into()],
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/safe_index.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/safe_index_add".as_slice())
            })
            .unwrap();
        let native_words = native.proc_code_words(id).unwrap();
        assert_eq!(
            linked.words[..native_words.len() - 1],
            native_words[..native_words.len() - 1]
        );
    }

    #[test]
    fn safe_member_assignment_uses_native_guard_order() {
        let ast = dm_syntax::parse("/proc/test(a, b)\n    a?.value = b\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()])
                .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let opcodes: Vec<_> = decoded
            .iter()
            .map(|instruction| instruction.opcode)
            .collect();
        assert_eq!(
            &opcodes[..6],
            [
                opcode::GET_VAR,
                318,
                opcode::PUSH_CACHE,
                opcode::GET_VAR,
                opcode::POP_CACHE,
                opcode::SET_VAR
            ]
        );
        assert_eq!(
            decoded[1].branch_targets().unwrap(),
            vec![decoded[6].offset as u32]
        );
    }

    #[test]
    fn catalog_calls_match_native_procedure_bodies() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/builtin_catalog.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/builtin_catalog.native.bin"
        ))
        .unwrap();
        for item in &ast.items {
            let path = item.header.split('(').next().unwrap();
            let Some(name) = path.strip_prefix("/proc/catalog_") else {
                continue;
            };
            if crate::builtin_catalog::lookup(name).is_none() {
                continue;
            }
            let params: Vec<String> = item
                .header
                .split_once('(')
                .and_then(|(_, tail)| tail.split_once(')'))
                .unwrap()
                .0
                .split(',')
                .map(|arg| arg.trim().to_owned())
                .collect();
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn alternate_builtin_arities_match_native_bodies() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/builtin_catalog.native.bin"
        ))
        .unwrap();
        for (name, expression, parameters) in [
            ("arctan2", "arctan(a,b)", vec!["a", "b"]),
            ("log2", "log(a,b)", vec!["a", "b"]),
            ("num2text2", "num2text(a,b)", vec!["a", "b"]),
            ("num2text3", "num2text(a,b,c)", vec!["a", "b", "c"]),
            ("ispath2", "ispath(a,b)", vec!["a", "b"]),
            ("locate3", "locate(a,b,c)", vec!["a", "b", "c"]),
            ("time2text3", "time2text(a,b,c)", vec!["a", "b", "c"]),
            ("rgb4", "rgb(a,b,c,d)", vec!["a", "b", "c", "d"]),
        ] {
            let path = format!("/proc/catalog_{name}");
            let source = format!(
                "{path}({})\n    return {expression}\n",
                parameters.join(",")
            );
            let ast = dm_syntax::parse(&source);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            let params: Vec<String> = parameters.iter().map(|name| (*name).into()).collect();
            let compiled =
                compile_simple_proc_with_params(&ast.items[0].children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn sized_local_arrays_match_native_bodies() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/local_array/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/local_array/probe.native.bin"
        ))
        .unwrap();
        for (item, params, path) in [
            (&ast.items[0], vec![], "/proc/test"),
            (&ast.items[1], vec!["n".into()], "/proc/test2"),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn multidimensional_local_array_matches_native_body() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/local_array_multi/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()])
                .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::Class, compiled.class_paths.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/local_array_multi/probe.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/test".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn bare_local_var_declaration_binds_its_name() {
        for source in [
            "/proc/test()\n    var amount = 3\n    return amount\n",
            "/proc/test()\n    var\tamount = 3\n    return amount\n",
        ] {
            let ast = dm_syntax::parse(source);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
            assert_eq!(compiled.local_names, ["amount"]);
        }
    }

    #[test]
    fn spawn_and_do_while_match_native_bodies() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/spawn_do_while/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/spawn_do_while/probe.native.bin"
        ))
        .unwrap();
        for (item, path) in [
            (&ast.items[0], "/proc/test"),
            (&ast.items[1], "/proc/spawn_test"),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &["n".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn infinity_literals_match_native_value_words() {
        for (literal, bits) in [
            ("1.#INF", f32::INFINITY.to_bits()),
            ("-1.#INF", f32::NEG_INFINITY.to_bits()),
        ] {
            let ast = dm_syntax::parse(&format!("/proc/test()\n    return {literal}\n"));
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(linked.words, [0x60, 42, bits >> 16, bits & 0xffff, 0x12, 0]);
        }
    }

    #[test]
    fn static_member_reads_use_native_selector_kind() {
        let ast = dm_syntax::parse("/proc/test(datum/x/path)\n    return path::abstract_type\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["path".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words[..8],
            [0x33, 0xffd9, 0, 0x34, 0xffd8, 0x33, 0xffe7, 0]
        );
    }

    #[test]
    fn inherited_class_static_member_uses_runtime_static_selector() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/static_inherited/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/static_inherited/probe.native.bin"
        ))
        .unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/probe_static_inherited".as_slice())
            })
            .unwrap();
        assert_eq!(native.proc_code_words(proc_id).unwrap(), &[80, 5, 18, 0]);
        let compiled = compile_simple_proc(&ast.items[2].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::Class, "/datum/static_inherited_base/child"),
                0,
            )
            .unwrap();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(decoded[0].opcode, opcode::PUSH_VAL);
        assert_eq!(decoded[0].operands, vec![32, 0]);
        assert_eq!(decoded[1].opcode, opcode::SET_VAR);
        assert_eq!(decoded[2].opcode, opcode::GET_VAR);
        assert_eq!(decoded[2].operands[0], 0xffe7);
    }

    #[test]
    fn named_calls_follow_native_argument_list_shapes() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/named_calls/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/named_calls/probe.native.bin"
        ))
        .unwrap();
        for (index, path, params) in [
            (1, "/proc/named", vec![]),
            (3, "/proc/member", vec!["x".into()]),
            (4, "/proc/newthing", vec![]),
        ] {
            let mut bindings = LowerBindings {
                parameters: params,
                ..LowerBindings::default()
            };
            bindings.global_procs.insert("f".into());
            let compiled =
                compile_simple_proc_with_bindings(&ast.items[index].children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            ledger
                .assign(Table::Class, compiled.class_paths.clone())
                .unwrap();
            ledger.assign(Table::Proc, vec!["/proc/f".into()]).unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
            let native_id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let expected =
                byond_dmb::bytecode::decode(native.proc_code_words(native_id).unwrap()).unwrap();
            assert_eq!(
                ours.iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>(),
                expected
                    .iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>(),
                "{path}"
            );
        }
    }

    #[test]
    fn initial_and_istype_use_native_static_reference_and_type_test() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/initial_istype/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/initial_istype/probe.native.bin"
        ))
        .unwrap();
        for (item, path, parameter, inferred) in [
            (&ast.items[1], "/proc/test", "x", false),
            (&ast.items[2], "/proc/istype_test", "x", false),
            (&ast.items[3], "/proc/istype_implicit", "x", true),
        ] {
            let mut bindings = LowerBindings {
                parameters: vec![parameter.into()],
                ..LowerBindings::default()
            };
            if inferred {
                bindings
                    .parameter_types
                    .insert(parameter.into(), "/datum/x".into());
            }
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            ledger
                .assign(Table::Class, compiled.class_paths.clone())
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let expected =
                byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
            assert_eq!(
                ours.iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>(),
                expected
                    .iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>(),
                "{path}"
            );
            if path == "/proc/test" {
                assert!(linked.words.contains(&0xffe7));
            }
        }
    }

    #[test]
    fn prefix_postfix_increment_and_index_match_native_bodies() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/incdec/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/incdec/probe.native.bin"
        ))
        .unwrap();
        for (item, path, params) in [
            (&ast.items[0], "/proc/post_statement", vec![]),
            (&ast.items[1], "/proc/pre_statement", vec![]),
            (&ast.items[2], "/proc/post_expr", vec![]),
            (&ast.items[3], "/proc/pre_expr", vec![]),
            (
                &ast.items[4],
                "/proc/post_index",
                vec!["x".into(), "i".into()],
            ),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn logical_assignments_match_native_short_circuit_bodies() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/logical_assignment/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/logical_assignment/probe.native.bin"
        ))
        .unwrap();
        for (item, path, params) in [
            (
                &ast.items[1],
                "/proc/or_assign",
                vec!["x".into(), "y".into()],
            ),
            (
                &ast.items[2],
                "/proc/and_assign",
                vec!["x".into(), "y".into()],
            ),
            (&ast.items[3], "/proc/member", vec!["x".into()]),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
            let expected =
                byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            assert_eq!(
                ours.iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>(),
                expected
                    .iter()
                    .map(|instruction| instruction.opcode)
                    .collect::<Vec<_>>(),
                "{path}"
            );
        }
    }

    #[test]
    fn indexed_logical_assignment_statement_and_expression_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/logical_index/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/logical_index/probe.native.bin"
        ))
        .unwrap();
        for (item, path, params) in [
            (
                &ast.items[0],
                "/proc/statement",
                vec!["x".into(), "i".into(), "y".into()],
            ),
            (
                &ast.items[1],
                "/proc/expression",
                vec!["x".into(), "i".into(), "y".into()],
            ),
            (
                &ast.items[2],
                "/proc/simple_expression",
                vec!["x".into(), "y".into()],
            ),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn shared_bindings_resolve_names_without_serializing_project_maps() {
        let ast = dm_syntax::parse("/proc/test()\n    return project_value + project_proc()\n");
        let mut shared = SharedLowerBindings::default();
        shared.globals.insert("project_value".into());
        shared.global_procs.insert("project_proc".into());
        shared.fingerprint = "project-digest".into();
        let bindings = LowerBindings {
            shared: Some(Arc::new(shared)),
            ..LowerBindings::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        assert!(compiled.code.items.iter().any(|item| matches!(item,
            CodeItem::Instruction(instruction) if instruction.opcode == opcode::CALL_GLOB)));
        let serialized = serde_json::to_string(&bindings).unwrap();
        assert!(!serialized.contains("project_value"));
        assert!(!serialized.contains("project-digest"));
    }

    #[test]
    fn shared_numeric_constants_respect_lexical_shadowing() {
        let ast = dm_syntax::parse(
            "/proc/constant()\n    return UNIX\n/proc/shadow(UNIX)\n    return UNIX\n",
        );
        let mut shared = SharedLowerBindings::default();
        shared
            .numeric_constants
            .insert("UNIX".into(), 3.0_f32.to_bits());
        let shared = Arc::new(shared);
        let constant = compile_simple_proc_with_bindings(
            &ast.items[0].children,
            &LowerBindings {
                shared: Some(shared.clone()),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let shadow = compile_simple_proc_with_bindings(
            &ast.items[1].children,
            &LowerBindings {
                parameters: vec!["UNIX".into()],
                shared: Some(shared),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let constant_words = link_proc(&constant.code, &Ledger::default()).unwrap().words;
        let shadow_words = link_proc(&shadow.code, &Ledger::default()).unwrap().words;
        assert_eq!(constant_words[0..2], [opcode::PUSH_INT, 3]);
        assert_eq!(shadow_words[0..3], [opcode::GET_VAR, 0xffd9, 0]);
    }

    #[test]
    fn shared_string_constants_respect_lexical_shadowing() {
        let ast = dm_syntax::parse(
            "/proc/constant()\n    return UNIX\n/proc/shadow(UNIX)\n    return UNIX\n",
        );
        let mut shared = SharedLowerBindings::default();
        shared.string_constants.insert("UNIX".into(), "UNIX".into());
        let shared = Arc::new(shared);
        let constant = compile_simple_proc_with_bindings(
            &ast.items[0].children,
            &LowerBindings {
                shared: Some(shared.clone()),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let shadow = compile_simple_proc_with_bindings(
            &ast.items[1].children,
            &LowerBindings {
                parameters: vec!["UNIX".into()],
                shared: Some(shared),
                ..LowerBindings::default()
            },
        )
        .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "UNIX"), 7)
            .unwrap();
        let constant_words = link_proc(&constant.code, &ledger).unwrap().words;
        let shadow_words = link_proc(&shadow.code, &ledger).unwrap().words;
        assert_eq!(constant_words[0..3], [opcode::PUSH_VAL, 6, 7]);
        assert_eq!(shadow_words[0..3], [opcode::GET_VAR, 0xffd9, 0]);
    }

    #[test]
    fn builtin_regex_and_icon_classes_use_native_datum_tag() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/builtin_classes/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/builtin_classes/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc(&item.children).unwrap();
            let mut ledger = Ledger::default();
            let (class, class_id) = if index == 0 {
                ("/regex", 20)
            } else {
                ("/icon", 15)
            };
            ledger
                .bind(crate::Symbol::new(Table::Class, class), class_id)
                .unwrap();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(linked.words, native.proc_code_words(index).unwrap());
        }
    }

    #[test]
    fn list_local_new_without_path_infers_list_type() {
        let ast = dm_syntax::parse(
            "/proc(test)\n    var/list/sorted_text = new()\n    return sorted_text\n",
        );
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert!(compiled.class_paths.contains(&"/list".into()));
    }

    #[test]
    fn existing_local_iterator_matches_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/existing_iterator/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/existing_iterator/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn nameof_proc_reference_folds_to_native_leaf_string() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/nameof/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/nameof/probe.native.bin"
        ))
        .unwrap();
        for (proc, path) in [
            (&ast.items[1], "/datum/x/proc/get"),
            (&ast.items[2], "/datum/x/proc/get2"),
        ] {
            let compiled = compile_simple_proc(&proc.children).unwrap();
            assert!(compiled.strings.contains(&"foo".into()));
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let native_code =
                byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let native_id = native_code[0].operands[1];
            assert_eq!(native.string(native_id), Some(b"foo".as_slice()));
            assert_eq!(linked.words[0], native.proc_code_words(id).unwrap()[0]);
        }
    }

    #[test]
    fn input_type_filters_and_choices_emit_native_prompt_operands() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/input_default/input_default.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/input_default/input_default.native.bin"
        ))
        .unwrap();
        for (index, path, mask, has_choices) in [
            (0, "/proc/implicit_prompt", 0, false),
            (1, "/proc/text_prompt", 4, false),
            (2, "/proc/implicit_choice", 0, true),
            (3, "/proc/anything_choice", 4096, true),
            (4, "/proc/implicit_short", 0, false),
            (5, "/proc/text_short", 4, false),
        ] {
            let params = if has_choices {
                vec!["choices".into()]
            } else {
                vec![]
            };
            let compiled =
                compile_simple_proc_with_params(&ast.items[index].children, &params).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            let expected =
                byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
            let input = ours
                .iter()
                .find(|instruction| instruction.opcode == 0xc1)
                .unwrap();
            let native_input = expected
                .iter()
                .find(|instruction| instruction.opcode == 0xc1)
                .unwrap();
            assert_eq!(input.operands, native_input.operands, "{path}");
            assert_eq!(input.operands, [mask, 0, if has_choices { 64 } else { 0 }]);
            assert!(ours.iter().any(|instruction| instruction.opcode == 0xba));
        }
    }

    #[test]
    fn color_input_uses_native_prompt_configuration() {
        let ast = dm_syntax::parse("/proc/test()\n    return input() as color\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(decoded[0].operands, [42, 18432, 0]);
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == 0xc6 && instruction.operands == [0, 0, 0]));
        assert!(decoded.iter().any(|instruction| instruction.opcode == 0xba));
    }

    #[test]
    fn in_list_and_range_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/in_range/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/in_range/probe.native.bin"
        ))
        .unwrap();
        for (item, path, params) in [
            (&ast.items[0], "/proc/range_check", vec!["x".into()]),
            (
                &ast.items[1],
                "/proc/list_member",
                vec!["x".into(), "L".into()],
            ),
        ] {
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn omitted_middle_call_argument_matches_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/call_hole/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let mut bindings = LowerBindings::default();
        bindings.global_procs.insert("call_hole_target".into());
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[1].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Proc, "/proc/call_hole_target"), 0)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/call_hole/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(1).unwrap());
    }

    #[test]
    fn weighted_pick_matches_native_switch_layout() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/weighted_pick/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/weighted_pick/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn dynamic_weighted_pick_matches_native_switch_layout() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/dynamic_pick/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/dynamic_pick/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn implicit_world_iterator_matches_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/implicit_for/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/datum/thing"), 0)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/implicit_for/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn typed_list_iterator_supplies_implicit_istype_path() {
        let ast = dm_syntax::parse(
            "/proc/probe(list/L)\n    for(var/datum/thing/M in L)\n        if(istype(M))\n            return M\n",
        );
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        assert!(compiled.class_paths.contains(&"/datum/thing".to_string()));
    }

    #[test]
    fn conditional_inferred_new_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/conditional_new/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/conditional_new/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/icon"), 15)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn locate_empty_typed_assignment_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/locate_empty/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/locate_empty/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/obj"), 4)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
        let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(1).unwrap());
    }

    #[test]
    fn arglist_dynamic_and_filter_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/arglist_dynamic/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/arglist_dynamic/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let params = match id {
                0 | 1 => vec!["fn", "L"],
                2 => vec!["L"],
                _ => vec!["target", "name", "L"],
            }
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn dynamic_colon_member_read_write_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/colon_member/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/colon_member/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(&item.children, &["D".into()]).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn raw_single_quote_text_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/raw_single_quote/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/raw_single_quote/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(native.string(437), Some(b"a\\n[b]".as_slice()));
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "a\\n[b]"), 437)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn escaped_apostrophe_and_angle_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/string_escapes/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/string_escapes/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc(&item.children).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn text_placeholder_templates_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/text_template/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/text_template/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let params = match id {
                0 => vec!["a", "b", "c"],
                1 => vec!["a", "b"],
                2 => vec![],
                3 => vec!["a"],
                _ => vec!["a", "b"],
            }
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn implicit_args_list_reads_and_writes_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/args_builtin/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/args_builtin/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let compiled =
                compile_simple_proc_with_params(&item.children, &["a".into(), "b".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }

        let shadow = dm_syntax::parse("/proc/probe()\n    var/args = 7\n    return args\n");
        let compiled = compile_simple_proc(&shadow.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert!(byond_dmb::bytecode::decode(&linked.words)
            .unwrap()
            .iter()
            .any(|instruction| instruction.opcode == opcode::GET_VAR
                && instruction.operands == [0xffda, 0]));
    }

    #[test]
    fn quoted_named_argument_key_matches_native_image_call() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/named_keys/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/named_keys/probe.native.bin"
        ))
        .unwrap();
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into()]).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn associative_list_constructor_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/named_keys/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/named_keys/probe.native.bin"
        ))
        .unwrap();
        for id in 1..4 {
            let params = if id == 3 {
                vec!["a".into(), "b".into()]
            } else {
                vec![]
            };
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn sorted_text_list_uses_typed_local_constructor() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/sortedtextlist/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["incoming".into(), "case_sensitive".into()],
        );
        assert!(compiled.is_ok());
    }

    #[test]
    fn member_arglist_and_colon_calls_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/member_arglist/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/member_arglist/probe.native.bin"
        ))
        .unwrap();
        for id in 1..4 {
            let params = if id == 3 {
                vec!["D".into()]
            } else {
                vec!["D".into(), "L".into()]
            };
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn generator_builtin_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/generator_alist.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/generator_alist.native.bin"
        ))
        .unwrap();
        for id in 0..4 {
            let params = if id == 1 {
                vec!["a", "b", "c"]
            } else {
                vec!["a", "b"]
            }
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn builtin_type_tags_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/builtin_type_tags/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/builtin_type_tags/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc(&item.children).unwrap();
            let mut ledger = Ledger::default();
            let (path, class_id) = if id < 2 {
                ("/mutable_appearance", 6)
            } else {
                ("/particles", 23)
            };
            ledger
                .bind(crate::Symbol::new(Table::Class, path), class_id)
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn grouped_augmented_assignment_target_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/group_target/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["A".into()]).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/group_target/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn icon_mixed_positional_and_named_args_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/icon_mixed/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["a".into(), "b".into()])
                .unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/icon_mixed/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn pair_iteration_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/for_pair.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/for_pair.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(&item.children, &["L".into()]).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn inferred_new_uses_declared_member_type() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/member_inferred_new/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/member_inferred_new/probe.native.bin"
        ))
        .unwrap();
        let mut shared = SharedLowerBindings::default();
        shared.member_types.insert(
            "/datum/holder".into(),
            HashMap::from([("entry".into(), "/datum/item".into())]),
        );
        shared
            .parent_types
            .insert("/datum/holder".into(), "/datum".into());
        let bindings = LowerBindings {
            parameters: vec!["H".into()],
            parameter_types: HashMap::from([("H".into(), "/datum/holder".into())]),
            shared: Some(Arc::new(shared)),
            ..LowerBindings::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[2].children, &bindings).unwrap();
        assert!(compiled.class_paths.contains(&"/datum/item".to_string()));
        let mut ledger = Ledger::default();
        let class_id = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id()) == Some(b"/datum/item".as_slice())
            })
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::Class, "/datum/item"),
                class_id as u32,
            )
            .unwrap();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());

        let compiled =
            compile_simple_proc_with_bindings(&ast.items[3].children, &bindings).unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/probe_type".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
    }

    #[test]
    fn qualified_global_reads_and_writes_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/global_qualified/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/global_qualified/probe.native.bin"
        ))
        .unwrap();
        let variable_id = native
            .variables
            .iter()
            .position(|variable| native.string(variable.name) == Some(b"foo".as_slice()))
            .unwrap();
        let bindings = LowerBindings {
            globals: BTreeSet::from(["foo".into()]),
            ..LowerBindings::default()
        };
        for (id, item) in ast.items.iter().enumerate().skip(1) {
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(
                    crate::Symbol::new(Table::Variable, "foo"),
                    variable_id as u32,
                )
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id - 1).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn list_bare_associative_keys_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/list_bare_keys/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["target".into()]).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/list_bare_keys/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn sound_constructor_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/sound_ctor/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/sound_ctor/probe.native.bin"
        ))
        .unwrap();
        for id in 0..3 {
            let params = if id == 2 { vec![] } else { vec!["a".into()] };
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn global_namespace_call_and_vars_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/global_namespace/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/global_namespace/probe.native.bin"
        ))
        .unwrap();
        let bindings = LowerBindings {
            global_procs: BTreeSet::from(["foo".into()]),
            ..LowerBindings::default()
        };
        for id in 1..3 {
            let compiled =
                compile_simple_proc_with_bindings(&ast.items[id].children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            if id == 1 {
                ledger
                    .bind(crate::Symbol::new(Table::Proc, "/proc/foo"), 0)
                    .unwrap();
            } else {
                ledger
                    .bind(
                        crate::Symbol::new(Table::Variable, BUILTIN_GLOBAL_VARS_SYMBOL),
                        177,
                    )
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn named_safe_method_call_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/safe_named_call/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/safe_named_call/probe.native.bin"
        ))
        .unwrap();
        let compiled =
            compile_simple_proc_with_params(&ast.items[1].children, &["D".into()]).unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let string_id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(1).unwrap());
    }

    #[test]
    fn typed_iterator_masks_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/remaining_forms.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/remaining_forms.native.bin"
        ))
        .unwrap();
        for id in 0..3 {
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &["L".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "iterator {id}"
            );
        }
    }

    #[test]
    fn src_and_global_arglist_calls_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/src_arglist/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/src_arglist/probe.native.bin"
        ))
        .unwrap();
        let bindings = LowerBindings {
            parameters: vec!["L".into()],
            global_procs: BTreeSet::from(["baz".into()]),
            ..LowerBindings::default()
        };
        for (item, id) in [(1, 1), (3, 3)] {
            let compiled =
                compile_simple_proc_with_bindings(&ast.items[item].children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            if item == 3 {
                ledger
                    .bind(crate::Symbol::new(Table::Proc, "/proc/baz"), 2)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn json_encode_flags_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/json_encode_flags/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/json_encode_flags/probe.native.bin"
        ))
        .unwrap();
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["value".into(), "flags".into()],
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn alert_and_issaved_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/alert_issaved.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/alert_issaved.native.bin"
        ))
        .unwrap();
        for id in [0usize, 1, 2, 3, 5, 6] {
            let item = ast
                .items
                .iter()
                .find(|item| {
                    item.header.contains(match id {
                        0 => "alert_one(",
                        1 => "alert_two(",
                        2 => "alert_four(",
                        3 => "alert_six(",
                        5 => "issaved_member(",
                        _ => "issaved_index(",
                    })
                })
                .unwrap();
            let param = if id < 5 { "M" } else { "D" };
            let compiled =
                compile_simple_proc_with_params(&item.children, &[param.into()]).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn untyped_array_new_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/inferred_array_new/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inferred_array_new/probe.native.bin"
        ))
        .unwrap();
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/list"), 0)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn compiler_context_constants_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/context_constants.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/context_constants.native.bin"
        ))
        .unwrap();
        for (id, path, owner) in [
            (0, "/proc/global_proc_name", None),
            (1, "/proc/global_type_name", None),
            (
                2,
                "/datum/context_probe/proc/member_proc_name",
                Some("/datum/context_probe"),
            ),
            (
                3,
                "/datum/context_probe/proc/member_type_name",
                Some("/datum/context_probe"),
            ),
        ] {
            let name = path.rsplit('/').next().unwrap();
            let item = ast
                .items
                .iter()
                .find(|item| item.header.contains(&format!("{name}(")))
                .unwrap();
            let bindings = LowerBindings {
                current_proc_path: Some(path.into()),
                current_type_path: owner.map(str::to_owned),
                ..LowerBindings::default()
            };
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            if id == 0 || id == 2 {
                ledger
                    .bind(crate::Symbol::new(Table::Proc, path), id)
                    .unwrap();
            }
            if id == 3 {
                ledger
                    .bind(crate::Symbol::new(Table::Class, "/datum/context_probe"), 0)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id as usize).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn constructor_arglist_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/new_arglist/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/new_arglist/probe.native.bin"
        ))
        .unwrap();
        for id in 0..2 {
            let params = if id == 0 {
                vec!["path".into(), "L".into()]
            } else {
                vec!["L".into()]
            };
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
            let mut ledger = Ledger::default();
            if id == 1 {
                ledger
                    .bind(crate::Symbol::new(Table::Class, "/datum"), 0)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn text_template_and_literal_share_utf8_string_key() {
        let ast = dm_syntax::parse("/proc/test()\n    return list(\"same\", text(\"same\"))\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(
            compiled
                .strings
                .iter()
                .filter(|key| compiled.string_bytes(key) == b"same")
                .count(),
            1
        );
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "same"), 0)
            .unwrap();
        link_proc(&compiled.code, &ledger).unwrap();
    }

    #[test]
    fn call_member_aug_lowers_without_unsupported_target() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/call_member_aug/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let item = ast
            .items
            .iter()
            .find(|item| item.header.contains("/proc/add("))
            .unwrap();
        let bindings = LowerBindings {
            parameters: vec!["D".into(), "n".into()],
            ..LowerBindings::default()
        };
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        let opcodes: Vec<_> = compiled
            .code
            .items
            .iter()
            .filter_map(|item| match item {
                CodeItem::Instruction(instruction) => Some(instruction.opcode),
                _ => None,
            })
            .collect();
        assert!(opcodes.contains(&opcode::AUG_ADD));
    }

    #[test]
    fn rgb_named_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/rgb_named/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/rgb_named/probe.native.bin"
        ))
        .unwrap();
        for id in 0..2 {
            let compiled = compile_simple_proc_with_params(
                &ast.items[id].children,
                &["a".into(), "b".into(), "c".into(), "d".into()],
            )
            .unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn dynamic_range_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/dynamic_range_step/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/dynamic_range_step/probe.native.bin"
        ))
        .unwrap();
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["n".into(), "s".into()])
                .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn parent_named_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/parent_named/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/parent_named/probe.native.bin"
        ))
        .unwrap();
        let compiled =
            compile_simple_proc_with_params(&ast.items[1].children, &["a".into(), "infix".into()])
                .unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(1).unwrap());
    }

    #[test]
    fn exception_type_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/exception_type/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/exception_type/probe.native.bin"
        ))
        .unwrap();
        for id in 0..2 {
            let bindings = LowerBindings {
                parameters: if id == 0 { vec!["E".into()] } else { vec![] },
                parameter_types: if id == 0 {
                    HashMap::from([("E".into(), "/exception".into())])
                } else {
                    HashMap::new()
                },
                ..LowerBindings::default()
            };
            let compiled =
                compile_simple_proc_with_bindings(&ast.items[id].children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Class, "/exception"), 19)
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn escaped_strings_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/string_escapes.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/string_escapes.native.bin"
        ))
        .unwrap();
        for id in 0..7 {
            let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap_or_else(|| panic!("native string missing: {key}"));
                ledger
                    .bind(crate::Symbol::new(Table::String, key), string_id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn builtin_arglist_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/builtin_arglist/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/builtin_arglist/probe.native.bin"
        ))
        .unwrap();
        for id in 0..3 {
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &["L".into()]).unwrap();
            let mut ledger = Ledger::default();
            if id == 1 {
                let string_id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == b"/generator")
                    .unwrap();
                ledger
                    .bind(
                        crate::Symbol::new(Table::String, "/generator"),
                        string_id as u32,
                    )
                    .unwrap();
            }
            if id == 2 {
                ledger
                    .bind(crate::Symbol::new(Table::Class, "/datum"), 0)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn typed_parameter_inferred_new_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/return_inferred_new/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/return_inferred_new/probe.native.bin"
        ))
        .unwrap();
        for id in 0..2 {
            let bindings = LowerBindings {
                parameters: vec!["p".into()],
                parameter_types: HashMap::from([("p".into(), "/datum/point".into())]),
                parameter_defaults: vec![Some(if id == 0 { "new" } else { "new(1)" }.into())],
                ..LowerBindings::default()
            };
            let compiled =
                compile_simple_proc_with_bindings(&ast.items[id].children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Class, "/datum/point"), 0)
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn typed_member_call_uses_native_static_proc_reference() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/proc_override_chain.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/proc_override_chain.native.bin"
        ))
        .unwrap();
        let shared = SharedLowerBindings {
            member_procs: HashMap::from([(
                "/datum/override_probe".into(),
                HashMap::from([(
                    "under_score".into(),
                    "/datum/override_probe/proc/under_score".into(),
                )]),
            )]),
            ..SharedLowerBindings::default()
        };
        let bindings = LowerBindings {
            parameters: vec!["D".into()],
            parameter_types: HashMap::from([("D".into(), "/datum/override_probe".into())]),
            shared: Some(Arc::new(shared)),
            ..LowerBindings::default()
        };
        for (name, id, target_id, target_path) in [
            (
                "invoke_source_name",
                6,
                3,
                "/datum/override_probe/proc/under_score",
            ),
            (
                "invoke_plain_typed",
                9,
                4,
                "/datum/override_probe/proc/plain_method",
            ),
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header.contains(&format!("{name}(")))
                .unwrap();
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            if id == 6 {
                ledger
                    .bind(crate::Symbol::new(Table::Proc, target_path), target_id)
                    .unwrap();
            } else {
                ledger
                    .bind(crate::Symbol::new(Table::String, "plain method"), 440)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn inc_length_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/inc_length/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/inc_length/probe.native.bin"
        ))
        .unwrap();
        for id in 0..2 {
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &["L".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn new_chain_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/new_chain/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/new_chain/probe.native.bin"
        ))
        .unwrap();
        let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/datum/thing"), 0)
            .unwrap();
        let string_id = native
            .strings
            .iter()
            .position(|entry| entry.data == b"InvokeAsync")
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::String, "InvokeAsync"),
                string_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(1).unwrap());
    }

    #[test]
    fn callback_constructor_chain_lowers() {
        let ast = dm_syntax::parse("/proc/probe(message)\n    return new /datum/callback/verb_callback(src, (nameof(/mob.proc/say)), message):InvokeAsync()\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["message".into()]).unwrap();
        assert!(compiled
            .class_paths
            .contains(&"/datum/callback/verb_callback".into()));
        assert!(compiled.strings.contains(&"InvokeAsync".into()));
    }

    #[test]
    fn istype_usr_matches_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/istype_usr/probe.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/istype_usr/probe.native.bin"
        ))
        .unwrap();
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/mob"), 0)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn particles_class_literal_and_constructor_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/particles_class/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/particles_class/probe.native.bin"
        ))
        .unwrap();
        for id in 0..2 {
            let compiled = compile_simple_proc(&ast.items[id].children).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Class, "/particles"), 23)
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn view_orange_and_turf_pick_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/view_orange.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/view_orange.native.bin"
        ))
        .unwrap();
        for id in 0..7 {
            let params = if id == 2 || id == 5 {
                vec!["A".into()]
            } else {
                vec![]
            };
            let compiled =
                compile_simple_proc_with_params(&ast.items[id].children, &params).unwrap();
            let mut ledger = Ledger::default();
            if id == 6 {
                let class_id = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap())
                    .unwrap()
                    .into_iter()
                    .find(|instruction| {
                        instruction.opcode == opcode::PUSH_VAL
                            && instruction.operands.first() == Some(&10)
                    })
                    .unwrap()
                    .operands[1];
                ledger
                    .bind(crate::Symbol::new(Table::Class, "/turf"), class_id)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn labeled_loops_and_comparison_flags_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/labeled_nested_iter/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/labeled_nested_iter/probe.native.bin"
        ))
        .unwrap();
        for (id, item) in ast.items.iter().enumerate() {
            let params = match id {
                0..=2 | 11 | 12 | 14 | 17 | 19 => vec!["L".into()],
                6..=8 => vec!["a".into(), "b".into()],
                10 => vec!["x".into()],
                _ => vec![],
            };
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let mut ledger = Ledger::default();
            if id == 16 {
                ledger
                    .bind(crate::Symbol::new(Table::Class, "/datum"), 0)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            if id == 18 {
                let native_code =
                    byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
                let ours = byond_dmb::bytecode::decode(&linked.words).unwrap();
                assert_eq!(
                    ours.iter()
                        .filter(|instruction| instruction.opcode == opcode::JMP_LOOP)
                        .count(),
                    native_code
                        .iter()
                        .filter(|instruction| instruction.opcode == opcode::JMP_LOOP)
                        .count()
                );
                continue;
            }
            if id == 10 {
                assert_eq!(
                    linked
                        .words
                        .windows(2)
                        .filter(|pair| pair == &[opcode::TEQ, opcode::POP])
                        .count(),
                    2
                );
                continue;
            }
            assert_eq!(
                linked.words,
                native.proc_code_words(id).unwrap(),
                "proc {id}"
            );
        }
    }

    #[test]
    fn sibling_labeled_loops_with_same_name_lower() {
        let ast = dm_syntax::parse("/proc/probe(list/L)\n    var/result = 0\n    if(L)\n        outer_loop:\n            for(var/x in L)\n                if(x)\n                    break outer_loop\n                result += x\n    if(L)\n        outer_loop:\n            for(var/y in L)\n                if(y)\n                    continue outer_loop\n                result += y\n    return result\n");
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        link_proc(&compiled.code, &Ledger::default()).unwrap();
    }

    #[test]
    fn shift_assignments_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/shift_assign/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/shift_assign/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(&item.children, &["x".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn implicit_return_preserves_dot_and_ends_like_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/implicit_return/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/implicit_return/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(&item.children, &["a".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn image_and_animate_calls_match_native_bytecode() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/builtin_catalog.native.bin"
        ))
        .unwrap();
        for (name, parameters, body) in [
            (
                "image_named",
                "a,b,c",
                "return image(icon=a, loc=b, layer=c)",
            ),
            ("image_mixed", "a,b", "return image(a, loc=b)"),
            ("image_one", "a", "return image(a)"),
            (
                "animate_named",
                "a,b",
                "animate(a, pixel_x=b, time=5)\n    return 1",
            ),
            ("animate_one", "a", "animate(a)\n    return 1"),
            ("animate_two", "a,b", "animate(a,b)\n    return 1"),
        ] {
            let path = format!("/proc/catalog_{name}");
            let source = format!("{path}({parameters})\n    {body}\n");
            let ast = dm_syntax::parse(&source);
            assert!(ast.diagnostics.is_empty(), "{name}: {:?}", ast.diagnostics);
            let params = parameters.split(',').map(str::to_owned).collect::<Vec<_>>();
            let compiled =
                compile_simple_proc_with_params(&ast.items[0].children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{path}");
        }
    }

    #[test]
    fn logical_chains_match_native_without_recursive_chain_lowering() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/logic_chain/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/logic_chain/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(
                &item.children,
                &["a".into(), "b".into(), "c".into()],
            )
            .unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
        let clauses = (0..40)
            .map(|_| "(a && b && c)")
            .collect::<Vec<_>>()
            .join(" || ");
        std::thread::Builder::new()
            .stack_size(1024 * 1024)
            .spawn(move || {
                let large =
                    dm_syntax::parse(&format!("/proc/large(a,b,c)\n    return {clauses}\n"));
                assert!(large.diagnostics.is_empty(), "{:?}", large.diagnostics);
                compile_simple_proc_with_params(
                    &large.items[0].children,
                    &["a".into(), "b".into(), "c".into()],
                )
                .unwrap();
            })
            .unwrap()
            .join()
            .unwrap();
    }

    #[test]
    fn equivalence_operators_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/equivalence/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/equivalence/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled =
                compile_simple_proc_with_params(&item.children, &["a".into(), "b".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(linked.words, native.proc_code_words(index).unwrap());
        }
    }

    #[test]
    fn hex_and_block_string_literals_match_native_bytecode() {
        let hex = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/raw_hex_literals/hex.dm"
        ));
        assert!(hex.diagnostics.is_empty(), "{:?}", hex.diagnostics);
        let native_hex = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/raw_hex_literals/hex.native.bin"
        ))
        .unwrap();
        for (index, item) in hex.items.iter().enumerate() {
            let compiled = compile_simple_proc(&item.children).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(linked.words, native_hex.proc_code_words(index).unwrap());
        }

        let raw = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/raw_hex_literals/raw.dm"
        ));
        assert!(raw.diagnostics.is_empty(), "{:?}", raw.diagnostics);
        let native_raw = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/raw_hex_literals/raw.native.bin"
        ))
        .unwrap();
        for (index, item) in raw.items.iter().enumerate() {
            let compiled = compile_simple_proc(&item.children).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native_raw
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap_or_else(|| panic!("native string missing: {key:?}"));
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(linked.words, native_raw.proc_code_words(index).unwrap());
        }
    }

    #[test]
    fn lexical_local_names_can_recur_in_distinct_branches_and_loops() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/reused_locals/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/reused_locals/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let params = if index == 0 {
                vec!["x".into()]
            } else {
                vec!["L".into()]
            };
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn dynamic_constructor_type_matches_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/dynamic_new/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["typepath".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/dynamic_new/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn bare_returns_end_native_frames_and_preserve_return_variable() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/bare_return.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/bare_return.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let params = if index == 2 {
                vec!["value".into()]
            } else {
                vec![]
            };
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            assert_eq!(
                link_proc(&compiled.code, &Ledger::default()).unwrap().words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn predefined_exception_and_regex_macro_expansions_match_native() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/predefined_macros.native.bin"
        ))
        .unwrap();
        let words = native.proc_code_words(0).unwrap();
        let file = std::str::from_utf8(&native.strings[words[8] as usize].data).unwrap();
        let source=format!("/proc/e(message)\n    return new /exception(message, {}, 2)\n/proc/r(message)\n    return regex(message,1)\n/proc/rr(message)\n    return regex(message,2)\n",serde_json::to_string(file).unwrap());
        let ast = dm_syntax::parse(&source);
        for (index, item) in ast.items.iter().enumerate() {
            let compiled =
                compile_simple_proc_with_params(&item.children, &["message".into()]).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Class, "/exception"), words[2])
                .unwrap();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|s| s.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            assert_eq!(
                link_proc(&compiled.code, &ledger).unwrap().words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn gradient_and_resource_output_forms_match_native() {
        for (source, bytes) in [
            (
                include_str!("../../../fixtures/native_compiler/gradient_output.dm"),
                include_bytes!("../../../fixtures/native_compiler/gradient_output.native.bin")
                    .as_slice(),
            ),
            (
                include_str!("../../../fixtures/native_compiler/addtext_link.dm"),
                include_bytes!("../../../fixtures/native_compiler/addtext_link.native.bin")
                    .as_slice(),
            ),
        ] {
            let ast = dm_syntax::parse(source);
            let native = byond_dmb::dmb::Dmb::from_bytes(bytes).unwrap();
            for (index, item) in ast.items.iter().enumerate() {
                let header = &item.header;
                let params = header
                    .split_once('(')
                    .unwrap()
                    .1
                    .trim_end_matches(')')
                    .split(',')
                    .map(|s| s.trim().to_owned())
                    .collect::<Vec<_>>();
                let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
                let mut ledger = Ledger::default();
                for key in &compiled.strings {
                    let id = native
                        .strings
                        .iter()
                        .position(|s| s.data == compiled.string_bytes(key))
                        .unwrap();
                    ledger
                        .bind(crate::Symbol::new(Table::String, key), id as u32)
                        .unwrap();
                }
                assert_eq!(
                    link_proc(&compiled.code, &ledger).unwrap().words,
                    native.proc_code_words(index).unwrap(),
                    "{}",
                    item.header
                );
            }
        }
    }

    #[test]
    fn stat_panels_and_missile_statements_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/stat_special.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/stat_special.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let params = match index {
                0 | 3 => vec!["a".into(), "b".into()],
                1 | 2 => vec!["a".into()],
                _ => vec!["a".into(), "b".into(), "c".into()],
            };
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            assert_eq!(
                link_proc(&compiled.code, &Ledger::default()).unwrap().words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn savefile_read_evaluates_complex_destinations_after_reading() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/input_complex.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/input_complex.native.bin"
        ))
        .unwrap();
        for (name, id, params) in [
            ("/proc/read_index", 6, vec!["S".into(), "L".into()]),
            ("/proc/read_dynamic_field", 8, vec!["S".into()]),
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(name))
                .unwrap();
            let bindings = LowerBindings {
                parameters: params,
                global_procs: BTreeSet::from(["get_holder".into()]),
                ..LowerBindings::default()
            };
            let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|s| s.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            ledger
                .bind(crate::Symbol::new(Table::Proc, "/proc/get_holder"), 7)
                .unwrap();
            assert_eq!(
                link_proc(&compiled.code, &ledger).unwrap().words,
                native.proc_code_words(id).unwrap(),
                "{name}"
            );
        }
    }

    #[test]
    fn savefile_read_write_statements_preserve_index_context() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/input_special.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/input_special.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let params = if index == 2 {
                vec!["value".into()]
            } else {
                vec!["source".into(), "value".into()]
            };
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|s| s.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn output_statements_and_special_forms_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/output_special.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/output_special.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let params = if matches!(index, 2..=5) {
                vec![
                    "target".into(),
                    "value".into(),
                    if index == 2 {
                        "options"
                    } else if index == 5 {
                        "control"
                    } else {
                        "name"
                    }
                    .into(),
                ]
            } else {
                vec!["target".into(), "value".into()]
            };
            let compiled = compile_simple_proc_with_params(&item.children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn safe_postfix_guards_cover_indices_members_and_calls_but_stop_at_groups() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/safe_postfix_chain/probe.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/safe_postfix_chain/probe.native.bin"
        ))
        .unwrap();
        for name in ["index_chain", "member_chain", "call_chain", "grouped_index"] {
            let path = format!("/proc/{name}");
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(&format!("{path}(")))
                .unwrap();
            let compiled = compile_simple_proc_with_bindings(
                &item.children,
                &LowerBindings {
                    parameters: vec!["L".into()],
                    parameter_types: HashMap::from([("L".into(), "/datum/chain_probe".into())]),
                    global_procs: BTreeSet::from(["index_key".into()]),
                    ..LowerBindings::default()
                },
            )
            .unwrap();
            let mut ledger = Ledger::default();
            ledger
                .assign(Table::String, compiled.strings.clone())
                .unwrap();
            ledger
                .assign(Table::Proc, ["/proc/index_key".into()])
                .unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            for words in [&linked.words[..], native.proc_code_words(id).unwrap()] {
                let decoded = byond_dmb::bytecode::decode(words).unwrap();
                let guard = decoded
                    .iter()
                    .find(|instruction| instruction.opcode == 317)
                    .unwrap();
                let target = guard.branch_targets().unwrap()[0] as usize;
                if name == "grouped_index" {
                    assert!(
                        target
                            <= decoded
                                .iter()
                                .find(|instruction| instruction.opcode == opcode::LIST_GET)
                                .unwrap()
                                .offset
                    );
                } else {
                    assert_eq!(
                        target,
                        decoded
                            .iter()
                            .find(|instruction| instruction.opcode == opcode::RET)
                            .unwrap()
                            .offset,
                        "{name}"
                    );
                }
            }
        }
    }

    #[test]
    fn renamed_verbs_use_native_verb_call_selectors() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/verb_call_selectors/probe.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/verb_call_selectors/probe.native.bin"
        ))
        .unwrap();
        let owner = "/mob/selector_probe";
        let verb = "/mob/selector_probe/verb/halt_probe";
        let shared = Arc::new(SharedLowerBindings {
            member_procs: HashMap::from([(
                owner.into(),
                HashMap::from([("halt_probe".into(), verb.into())]),
            )]),
            ..SharedLowerBindings::default()
        });
        for (child, parameters) in [(1, vec![]), (2, vec!["M".into()])] {
            let compiled = compile_simple_proc_with_bindings(
                &ast.items[0].children[child].children,
                &LowerBindings {
                    parameters,
                    parameter_types: HashMap::from([("M".into(), owner.into())]),
                    current_type_path: Some(owner.into()),
                    shared: Some(shared.clone()),
                    ..LowerBindings::default()
                },
            )
            .unwrap();
            let mut ledger = Ledger::default();
            ledger.assign(Table::Proc, [verb.into()]).unwrap();
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert!(linked.words.contains(&0xffe0));
            assert!(!linked.words.contains(&0xffdf));
            let path = format!(
                "{owner}/proc/{}",
                if child == 1 {
                    "bare_probe"
                } else {
                    "member_probe"
                }
            );
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert!(native
                .proc_code_words(id)
                .unwrap()
                .contains(&if child == 1 { 0xffe0 } else { 0xffde }));
        }
    }

    #[test]
    fn current_and_inherited_members_shadow_global_procedures() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/member_global_shadowing/probe.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/member_global_shadowing/probe.native.bin"
        ))
        .unwrap();
        let shared = Arc::new(SharedLowerBindings {
            global_procs: BTreeSet::from(["collision".into()]),
            known_member_procs: HashMap::from([(
                "/datum/shadow".into(),
                BTreeSet::from(["collision".into()]),
            )]),
            parent_types: HashMap::from([("/datum/shadow/child".into(), "/datum/shadow".into())]),
            ..SharedLowerBindings::default()
        });
        for (index, owner, path, expected) in [
            (2, "/datum/shadow", "/datum/shadow/proc/probe", opcode::CALL),
            (
                3,
                "/datum/shadow/child",
                "/datum/shadow/child/proc/inherited_probe",
                opcode::CALL,
            ),
            (
                4,
                "/datum/shadow",
                "/datum/shadow/proc/explicit_global",
                opcode::CALL_GLOB,
            ),
        ] {
            let compiled = compile_simple_proc_with_bindings(
                &ast.items[index].children,
                &LowerBindings {
                    current_type_path: Some(owner.into()),
                    shared: Some(shared.clone()),
                    ..LowerBindings::default()
                },
            )
            .unwrap();
            let calls: Vec<_> = compiled
                .code
                .items
                .iter()
                .filter_map(|item| match item {
                    CodeItem::Instruction(instruction)
                        if matches!(instruction.opcode, opcode::CALL | opcode::CALL_GLOB) =>
                    {
                        Some(instruction.opcode)
                    }
                    _ => None,
                })
                .collect();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(
                native.proc_code_words(id).unwrap()[0],
                expected as u32,
                "{path}"
            );
            assert_eq!(calls, vec![expected], "{path}");
        }
    }

    #[test]
    fn bound_project_rejects_unknown_bare_calls_but_allows_dynamic_members() {
        let ast = dm_syntax::parse("/proc/probe(receiver)\n    missing_builtin()\n");
        assert!(
            compile_simple_proc_with_params(&ast.items[0].children, &["receiver".into()]).is_ok()
        );
        let bindings = LowerBindings {
            parameters: vec!["receiver".into()],
            shared: Some(Arc::new(SharedLowerBindings::default())),
            ..LowerBindings::default()
        };
        let errors =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap_err();
        assert!(errors[0]
            .reason
            .contains("unresolved unqualified procedure: missing_builtin"));
        let dynamic = dm_syntax::parse("/proc/probe(receiver)\n    receiver.dynamic_method()\n");
        assert!(compile_simple_proc_with_bindings(&dynamic.items[0].children, &bindings).is_ok());
        let inherited = dm_syntax::parse("/datum/child/proc/probe()\n    declared_method()\n");
        let bindings = LowerBindings {
            current_type_path: Some("/datum/child".into()),
            shared: Some(Arc::new(SharedLowerBindings {
                known_member_procs: HashMap::from([(
                    "/datum/parent".into(),
                    BTreeSet::from(["declared_method".into()]),
                )]),
                parent_types: HashMap::from([("/datum/child".into(), "/datum/parent".into())]),
                ..SharedLowerBindings::default()
            })),
            ..LowerBindings::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&inherited.items[0].children, &bindings).unwrap();
        assert!(compiled.strings.contains(&"declared method".into()));
    }

    #[test]
    fn crash_vector_and_variadic_text_comparisons_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/special_builtins.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/special_builtins.native.bin"
        ))
        .unwrap();
        let parameters = [
            vec!["value"],
            vec![],
            vec!["a", "b"],
            vec!["a", "b", "c"],
            vec!["a", "b", "c"],
            vec![],
            vec!["a", "b", "c"],
        ];
        for (index, names) in parameters.iter().enumerate() {
            let params = names
                .iter()
                .map(|name| (*name).to_owned())
                .collect::<Vec<_>>();
            let compiled =
                compile_simple_proc_with_params(&ast.items[index].children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn load_ext_and_handle_calls_match_native() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/load_ext.dm"
        ));
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/load_ext.native.bin"
        ))
        .unwrap();
        for (index, parameters) in [
            vec!["library", "function"],
            vec!["function", "value"],
            vec!["function", "values"],
        ]
        .iter()
        .enumerate()
        {
            let params = parameters
                .iter()
                .map(|name| (*name).to_owned())
                .collect::<Vec<_>>();
            let compiled =
                compile_simple_proc_with_params(&ast.items[index].children, &params).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn chained_dynamic_and_external_calls_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/chained_call/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/chained_call/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let parameter = if index == 0 { "target" } else { "library" };
            let compiled =
                compile_simple_proc_with_params(&item.children, &[parameter.into()]).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn proc_path_literal_uses_proc_table_value_tag() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/proc_path_literal/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[1].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Proc, "/proc/foo"), 0)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/proc_path_literal/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(linked.words, native.proc_code_words(1).unwrap());
    }

    #[test]
    fn named_filter_matches_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/filter_named/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with("/proc/probe_filter("))
            .unwrap();
        let compiled =
            compile_simple_proc_with_params(&item.children, &["a".into(), "b".into()]).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/filter_named/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/probe_filter".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn indexed_augmented_assignment_preserves_native_evaluation_order() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/index_aug/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/index_aug/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(
                &item.children,
                &["L".into(), "i".into(), "x".into()],
            )
            .unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn single_target_chained_calls_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/chained_call_one/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/chained_call_one/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let compiled = compile_simple_proc_with_params(&item.children, &["fn".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(linked.words, native.proc_code_words(index).unwrap());
        }
    }

    #[test]
    fn initial_dynamic_index_and_colon_member_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/initial_dynamic/probe.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/initial_dynamic/probe.native.bin"
        ))
        .unwrap();
        for (index, item) in ast.items.iter().enumerate() {
            let parameters = if index == 0 {
                vec!["D".into(), "name".into()]
            } else {
                vec!["D".into()]
            };
            let compiled = compile_simple_proc_with_params(&item.children, &parameters).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(
                linked.words,
                native.proc_code_words(index).unwrap(),
                "proc {index}"
            );
        }
    }

    #[test]
    fn lone_closing_bracket_is_literal_string_content() {
        let (bytes, interpolations) = parse_interpolated_string("] and \\] and \\[").unwrap();
        assert_eq!(bytes, b"] and ] and [");
        assert!(interpolations.is_empty());
    }

    #[test]
    fn closing_bracket_strings_match_native_bytecode() {
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/native_compiler/string_bracket_semantics.dm"
        ));
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/string_bracket_semantics.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for key in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == compiled.string_bytes(key))
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, key), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(0).unwrap());
    }

    #[test]
    fn typed_local_infers_constructor_path() {
        let ast = dm_syntax::parse(
            "/proc/create()\n    var/datum/expedition_building/B = new(3)\n    return B\n",
        );
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.class_paths, vec!["/datum/expedition_building"]);
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::Class, "/datum/expedition_building"),
                7,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::NEW));
        let bare = dm_syntax::parse(
            "/proc/create()\n    var/datum/expedition_building/B = new\n    return B\n",
        );
        assert!(bare.diagnostics.is_empty(), "{:?}", bare.diagnostics);
        let bare_compiled = compile_simple_proc(&bare.items[0].children).unwrap();
        assert_eq!(
            bare_compiled.class_paths,
            vec!["/datum/expedition_building"]
        );
        let reassigned = dm_syntax::parse(
            "/proc/create()\n    var/datum/expedition_building/B\n    B = new(3)\n    return B\n",
        );
        let reassigned_compiled = compile_simple_proc(&reassigned.items[0].children).unwrap();
        assert_eq!(
            reassigned_compiled.class_paths,
            vec!["/datum/expedition_building"]
        );
    }

    #[test]
    fn literal_arithmetic_return_decodes_as_native_instructions() {
        let ast = dm_syntax::parse("/proc/test()\n  return 2 + 3 * 4\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(
            decoded.iter().map(|i| i.opcode).collect::<Vec<_>>(),
            [0x50, 0x12, 0]
        );
    }

    #[test]
    fn local_assignment_and_string_reference_link() {
        let ast = dm_syntax::parse("/proc/test()\n  var/x = \"hello\"\n  x = 3\n  return x\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.strings, ["hello"]);
        assert_eq!(compiled.local_count, 1);
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert!(linked
            .relocations
            .iter()
            .any(|(_, symbol)| symbol.key == "hello"));
        assert!(byond_dmb::bytecode::decode(&linked.words).is_ok());
    }

    #[test]
    fn unsupported_control_flow_fails_closed() {
        let ast = dm_syntax::parse("/proc/test()\n  switch(1)\n    return 2\n");
        assert!(compile_simple_proc(&ast.items[0].children).is_err());
    }

    #[test]
    fn branches_and_loops_have_valid_native_targets() {
        let ast = dm_syntax::parse("/proc/test(x)\n  var/y = 1\n  while(x)\n    x = x - 1\n  if(y)\n    return x\n  else\n    return 0\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let starts: BTreeSet<_> = decoded.iter().map(|i| i.offset as u32).collect();
        for instruction in decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn nested_break_and_continue_target_the_nearest_loop() {
        let ast = dm_syntax::parse("/proc/test(x)\n  while(x)\n    while(x)\n      continue\n      break\n    break\n  return x\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset as u32)
            .collect();
        for instruction in decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
        let invalid = dm_syntax::parse("/proc/test()\n  break\n");
        assert!(compile_simple_proc(&invalid.items[0].children).is_err());
    }

    #[test]
    fn lists_sleep_and_boolean_branches_decode() {
        let ast = dm_syntax::parse(
            "/proc/test(x)\n  var/items = list(1, 2)\n  if(x && 1)\n    sleep(1)\n  return items\n",
        );
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let instructions = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == opcode::NEW_LIST));
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == opcode::SLEEP));
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == opcode::JMP_AND));
        let associative = dm_syntax::parse("/proc/test()\n  return list(\"key\" = 1)\n");
        let compiled = compile_simple_proc(&associative.items[0].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert!(byond_dmb::bytecode::decode(&linked.words)
            .unwrap()
            .iter()
            .any(|ins| ins.opcode == 0xc8));
    }

    #[test]
    fn else_if_chain_has_valid_targets() {
        let ast = dm_syntax::parse("/proc/test(x)\n  if(x == 1)\n    return 10\n  else if(x == 2)\n    return 20\n  else\n    return 30\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset as u32)
            .collect();
        for instruction in decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn augmented_assignments_decode_without_stack_pop() {
        let ast = dm_syntax::parse("/proc/test()\n  var/x = 1\n  x += 2\n  x &= 3\n  return x\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::AUG_ADD));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::AUG_BAND));
    }

    #[test]
    fn c_style_for_with_continue_and_break_has_valid_branches() {
        let ast = dm_syntax::parse("/proc/test(n)\n  var/result = 0\n  for(var/i = 0; i < n; i = i + 1)\n    if(i == 2)\n      continue\n    if(i == 5)\n      break\n    result += i\n  return result\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["n".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset as u32)
            .collect();
        for instruction in decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn switch_cases_compare_a_single_evaluated_selector() {
        let ast = dm_syntax::parse("/proc/test(x)\n  switch(x)\n    if(1)\n      return 10\n    if(2)\n      return 20\n    else\n      return 30\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        assert_eq!(compiled.local_count, 1);
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(
            decoded
                .iter()
                .filter(|instruction| instruction.opcode == opcode::TEQ)
                .count(),
            2
        );
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset as u32)
            .collect();
        for instruction in decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn range_for_supports_ascending_and_descending_steps() {
        for control in [
            "var/i = 1 to n step 2",
            "var/i = 5 to n step -1",
            "var/i in 1 to n",
        ] {
            let source = format!("/proc/test(n)\n  var/result = 0\n  for({control})\n    result += i\n  return result\n");
            let ast = dm_syntax::parse(&source);
            let compiled =
                compile_simple_proc_with_params(&ast.items[0].children, &["n".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
            assert!(decoded.iter().any(|instruction| instruction.opcode
                == if control.contains("step") { 0xff } else { 0xfd }));
            assert_eq!(compiled.local_count, 2);
        }
    }

    #[test]
    fn switch_alternatives_and_inclusive_range_decode() {
        let ast = dm_syntax::parse("/proc/test(x)\n  switch(x)\n    if(1, 2)\n      return 10\n    if(3 to 5)\n      return 20\n    else\n      return 0\n");
        let typed = dm_syntax::parse_body_items(&ast.items[0].children);
        assert!(typed.diagnostics.is_empty());
        assert!(matches!(
            typed.statements[0].kind,
            StatementKind::Switch { .. }
        ));
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(
            decoded
                .iter()
                .filter(|instruction| instruction.opcode == opcode::TEQ)
                .count(),
            2
        );
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::TGE));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::TLE));
    }

    #[test]
    fn switch_break_targets_switch_and_continue_targets_outer_loop() {
        let ast = dm_syntax::parse("/proc/test(x)\n  while(x)\n    switch(x)\n      if(1)\n        break\n      else\n        continue\n    return x\n  return 0\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset as u32)
            .collect();
        for instruction in decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn member_reads_writes_and_calls_link_through_receiver() {
        let ast = dm_syntax::parse(
            "/proc/test(obj)\n  obj.value = 3\n  obj.update(2)\n  return obj.value\n",
        );
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["obj".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::SET_VAR));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::CALL));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::GET_VAR));
    }

    #[test]
    fn indexed_reads_and_writes_use_native_stack_order() {
        let ast =
            dm_syntax::parse("/proc/test(items, key)\n  items[key] = 7\n  return items[key]\n");
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["items".into(), "key".into()],
        )
        .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let names: Vec<_> = decoded
            .iter()
            .map(|instruction| instruction.opcode)
            .collect();
        assert!(names.contains(&opcode::LIST_SET));
        assert!(names.contains(&opcode::LIST_GET));
        let set = decoded
            .iter()
            .position(|instruction| instruction.opcode == opcode::LIST_SET)
            .unwrap();
        assert_eq!(decoded[set - 3].opcode, opcode::PUSH_INT);
        assert_eq!(decoded[set - 2].opcode, opcode::GET_VAR);
        assert_eq!(decoded[set - 1].opcode, opcode::GET_VAR);
    }

    #[test]
    fn computed_receiver_call_preserves_cache_across_arguments() {
        let ast = dm_syntax::parse("/proc/test(x)\n  return make(x).update(2)\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::PUSH_CACHE));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::POP_CACHE));
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::CALL));
    }

    #[test]
    fn computed_index_receiver_reads_field_from_cache() {
        let ast = dm_syntax::parse("/proc/test(items, key)\n  return items[key].value\n");
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["items".into(), "key".into()],
        )
        .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .assign(Table::String, compiled.strings.clone())
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let sequence: Vec<_> = decoded
            .iter()
            .map(|instruction| instruction.opcode)
            .collect();
        assert!(sequence
            .windows(3)
            .any(|ops| ops == [opcode::LIST_GET, opcode::SET_VAR, opcode::GET_VAR]));
        let get = decoded
            .iter()
            .find(|instruction| {
                instruction.opcode == opcode::GET_VAR && instruction.operands.len() == 1
            })
            .unwrap();
        assert_eq!(get.operands[0], 0);
    }

    #[test]
    fn computed_receiver_assignment_matches_native_order() {
        let source = "/proc/test(a,b)\n  logical_identity(a).value = (a = b)\n  return a\n";
        let ast = dm_syntax::parse(source);
        let mut bindings = LowerBindings {
            parameters: vec!["a".into(), "b".into()],
            ..LowerBindings::default()
        };
        bindings.global_procs.insert("logical_identity".into());
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "value"), 437)
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::Proc, "/proc/logical_identity"), 3)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/logical_fields.native.bin"
        ))
        .unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(b"field_statement_call_mutate"))
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
        let expression =
            dm_syntax::parse("/proc/test(a,b)\n  return logical_identity(a).value = (a = b)\n");
        let compiled_expr =
            compile_simple_proc_with_bindings(&expression.items[0].children, &bindings).unwrap();
        let linked_expr = link_proc(&compiled_expr.code, &ledger).unwrap();
        let expr_id = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(b"field_expr_call_mutate"))
            })
            .unwrap();
        assert_eq!(linked_expr.words, native.proc_code_words(expr_id).unwrap());
    }

    #[test]
    fn src_call_uses_native_compound_variable() {
        let ast = dm_syntax::parse("/proc/test()\n  return foo(1)\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "foo"), 438)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert!(linked
            .words
            .windows(6)
            .any(|w| w == [0x29, 0xffdc, 0xffce, 0xffdd, 438, 1]));
    }

    #[test]
    fn native_simple_fixture_matches_compiled_bodies() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/simple.native.bin"
        ))
        .unwrap();
        let names: Vec<_> = native
            .procs
            .iter()
            .enumerate()
            .filter_map(|(id, proc)| {
                let name = String::from_utf8_lossy(native.string(proc.strings[0])?).into_owned();
                name.contains("return_").then(|| {
                    (
                        name,
                        id,
                        native.proc_code_words(id).unwrap_or_default().to_vec(),
                    )
                })
            })
            .collect();
        assert_eq!(names.len(), 3);
        let source = dm_syntax::parse(include_str!("../../../fixtures/native_compiler/simple.dm"));
        for (item, (name, _, expected)) in source.items.iter().zip(&names) {
            let compiled = compile_simple_proc(&item.children).unwrap();
            let mut ledger = Ledger::default();
            for string in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == string.as_bytes())
                    .unwrap() as u32;
                ledger
                    .bind(crate::Symbol::new(Table::String, string), id)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            assert_eq!(&linked.words, expected, "{name}");
        }
    }

    #[test]
    fn native_flow_fixture_matches_compiled_bodies_and_metadata() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/flow.native.bin"
        ))
        .unwrap();
        let source = dm_syntax::parse(include_str!("../../../fixtures/native_compiler/flow.dm"));
        for item in &source.items {
            let name = item.header.split('(').next().unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| native.string(proc.strings[0]) == Some(name.as_bytes()))
                .unwrap();
            let native_proc = &native.procs[id];
            let compiled = compile_simple_proc_with_params(&item.children, &["x".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
            let local_words = &native.lists[native_proc.code_locals_args[1] as usize];
            let expected_local_names = local_words
                .iter()
                .map(|id| {
                    let variable = &native.variables[*id as usize];
                    String::from_utf8_lossy(native.string(variable.name).unwrap()).into_owned()
                })
                .collect::<Vec<_>>();
            assert_eq!(compiled.local_names, expected_local_names, "{name} locals");
            let expected_args = native.proc_arguments(id).unwrap();
            let arguments = compiled.argument_metadata();
            assert_eq!(arguments.len(), expected_args.len());
            for (actual, expected) in arguments.iter().zip(expected_args) {
                assert_eq!(
                    (actual.type_flags, actual.value_source, actual.reserved),
                    (
                        expected.type_flags,
                        expected.value_source,
                        expected.reserved
                    )
                );
                assert_eq!(
                    native.string(native.variables[expected.variable_id as usize].name),
                    Some(actual.name.as_bytes())
                );
            }
        }
    }

    #[test]
    fn native_iterator_setup_matches_paired_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/iterator_parity.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/iterator_parity.dm"
        ));
        for name in ["iterator_untyped", "iterator_anything"] {
            let proc = ast
                .items
                .iter()
                .find(|item| item.header.contains(name))
                .unwrap();
            let compiled = compile_simple_proc_with_params(&proc.children, &["L".into()]).unwrap();
            let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| {
                    native
                        .string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            let native_words = native.proc_code_words(id).unwrap();
            assert_eq!(
                &linked.words[..18],
                &native_words[..18],
                "{name} iterator setup"
            );
        }
        let proc = ast
            .items
            .iter()
            .find(|item| item.header.contains("iterator_typed"))
            .unwrap();
        let compiled = compile_simple_proc_with_params(&proc.children, &["L".into()]).unwrap();
        let class_id = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id()) == Some(b"/datum/iterator_probe".as_slice())
            })
            .unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::Class, "/datum/iterator_probe"),
                class_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(b"iterator_typed"))
            })
            .unwrap();
        assert_eq!(
            &linked.words[..28],
            &native.proc_code_words(id).unwrap()[..28]
        );
    }

    #[test]
    fn absolute_constructor_matches_native_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/const_null_bindings/same_null.native.bin"
        ))
        .unwrap();
        let class_id = native
            .classes
            .iter()
            .position(|class| {
                native.string(class.path_string_id()) == Some(b"/datum/base".as_slice())
            })
            .unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| {
                native
                    .string(proc.strings[0])
                    .is_some_and(|path| path.ends_with(b"owner"))
            })
            .unwrap();
        let ast = dm_syntax::parse("/proc/owner()\n  return new /datum/base\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.class_paths, ["/datum/base"]);
        let mut ledger = Ledger::default();
        ledger
            .bind(
                crate::Symbol::new(Table::Class, "/datum/base"),
                class_id as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
    }

    #[test]
    fn absolute_constructor_accepts_arguments() {
        let ast = dm_syntax::parse("/proc/make()\n  return new /datum/base(7, \"seed\")\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.class_paths, ["/datum/base"]);
        assert_eq!(compiled.strings, ["seed"]);
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/datum/base"), 23)
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::String, "seed"), 42)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|instruction| instruction.opcode == opcode::NEW));
    }

    #[test]
    fn file_and_icon_constructors_link_resource_literals() {
        for name in ["file", "icon"] {
            let ast = dm_syntax::parse(&format!("/proc/make()\n  return {name}('asset.txt')\n"));
            let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
            assert_eq!(compiled.resources, ["asset.txt"]);
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Resource, "asset.txt"), 7)
                .unwrap();
            if name == "icon" {
                ledger
                    .bind(crate::Symbol::new(Table::String, "/icon"), 29)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
            assert!(decoded
                .iter()
                .any(|instruction| instruction.opcode == opcode::NEW));
        }
    }

    #[test]
    fn named_icon_matches_native_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/constructor_branch_entries/probe.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse("/proc/icon_named(flag,path)\n  if(!flag)\n    return\n  return icon(icon=path, icon_state=\"x\")\n");
        let compiled = compile_simple_proc_with_params(
            &ast.items[0].children,
            &["flag".into(), "path".into()],
        )
        .unwrap();
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.as_bytes())
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, string), id as u32)
                .unwrap();
        }
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/icon_named".as_slice()))
            .unwrap();
        let native_words = native.proc_code_words(proc_id).unwrap();
        assert_eq!(&linked.words[8..], &native_words[8..]);
    }

    #[test]
    fn typed_local_declarations_bind_leaf_names() {
        let ast = dm_syntax::parse("/proc/locals()\n  var/list/items = list(1)\n  var/obj/item/tool = null\n  return items\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        assert_eq!(compiled.local_names, ["items", "tool"]);
        link_proc(&compiled.code, &Ledger::default()).unwrap();
    }

    #[test]
    fn nested_ternary_branches_leave_a_value() {
        let ast = dm_syntax::parse("/proc/choose(x,y)\n  return x ? 1 : y ? 2 : 3\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into(), "y".into()])
                .unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(
            decoded
                .iter()
                .filter(|instruction| instruction.opcode == opcode::JZ)
                .count(),
            2
        );
        let starts: BTreeSet<_> = decoded
            .iter()
            .map(|instruction| instruction.offset as u32)
            .collect();
        for instruction in &decoded {
            for target in instruction.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn try_catch_matches_native_fixture_shape() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/try_join_cleanup/probe.native.bin"
        ))
        .unwrap();
        let source = include_str!("../../../fixtures/translation/try_join_cleanup/probe.dm");
        let ast = dm_syntax::parse(source);
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with("/proc/join_if_else("))
            .unwrap();
        let bindings = LowerBindings {
            parameters: vec!["x".into()],
            global_procs: ["join_helper".into()].into(),
            ..LowerBindings::default()
        };
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        assert_eq!(compiled.local_names, ["e"]);
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.as_bytes())
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, string), id as u32)
                .unwrap();
        }
        let helper = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/join_helper".as_slice())
            })
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::Proc, "/proc/join_helper"),
                helper as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/join_if_else".as_slice())
            })
            .unwrap();
        let actual = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let expected = byond_dmb::bytecode::decode(native.proc_code_words(id).unwrap()).unwrap();
        assert_eq!(
            actual
                .iter()
                .take(expected.len() - 1)
                .map(|ins| ins.opcode)
                .collect::<Vec<_>>(),
            expected
                .iter()
                .take(expected.len() - 1)
                .map(|ins| ins.opcode)
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn nested_try_throw_has_valid_targets_and_catch_slots() {
        let ast = dm_syntax::parse("/proc/guard(x)\n  try\n    try\n      if(x)\n        throw \"inner\"\n    catch(var/exception/inner)\n      throw inner\n  catch(var/outer)\n    return outer\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        assert_eq!(compiled.local_names, ["inner", "outer"]);
        let ledger = Ledger::default();
        let mut ledger = ledger;
        ledger
            .bind(crate::Symbol::new(Table::String, "inner"), 1)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(decoded.iter().filter(|ins| ins.opcode == 0x12c).count(), 2);
        assert_eq!(decoded.iter().filter(|ins| ins.opcode == 0x12e).count(), 2);
        assert_eq!(decoded.iter().filter(|ins| ins.opcode == 0x12d).count(), 2);
        let starts: BTreeSet<_> = decoded.iter().map(|ins| ins.offset as u32).collect();
        for ins in decoded {
            for target in ins.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn catch_without_binding_matches_native_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/try_empty.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!("../../../fixtures/translation/try_empty.dm"));
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["value".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let id = native
            .procs
            .iter()
            .position(|proc| native.string(proc.strings[0]) == Some(b"/proc/try_empty".as_slice()))
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(id).unwrap());
    }

    #[test]
    fn continue_exiting_inner_try_uses_tryjmp() {
        let ast = dm_syntax::parse("/proc/loop(x)\n  while(x)\n    try\n      x = x - 1\n      continue\n    catch(var/e)\n      return e\n  return x\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded.iter().any(|ins| ins.opcode == 0x12f));
        let starts: BTreeSet<_> = decoded.iter().map(|ins| ins.offset as u32).collect();
        for ins in decoded {
            for target in ins.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn goto_exiting_try_uses_native_tryjmp() {
        let source = include_str!("../../../fixtures/translation/try_join_cleanup/probe.dm");
        let ast = dm_syntax::parse(source);
        let item = ast
            .items
            .iter()
            .find(|item| item.header.starts_with("/proc/join_goto_out("))
            .unwrap();
        let bindings = LowerBindings {
            parameters: vec!["x".into()],
            global_procs: ["join_helper".into()].into(),
            ..LowerBindings::default()
        };
        let compiled = compile_simple_proc_with_bindings(&item.children, &bindings).unwrap();
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/try_join_cleanup/probe.native.bin"
        ))
        .unwrap();
        let mut ledger = Ledger::default();
        for string in &compiled.strings {
            let id = native
                .strings
                .iter()
                .position(|entry| entry.data == string.as_bytes())
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, string), id as u32)
                .unwrap();
        }
        let helper = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/join_helper".as_slice())
            })
            .unwrap();
        ledger
            .bind(
                crate::Symbol::new(Table::Proc, "/proc/join_helper"),
                helper as u32,
            )
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let native_id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/join_goto_out".as_slice())
            })
            .unwrap();
        assert_eq!(linked.words, native.proc_code_words(native_id).unwrap());
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded.iter().any(|ins| ins.opcode == 0x12f));
        let starts: BTreeSet<_> = decoded.iter().map(|ins| ins.offset as u32).collect();
        for ins in decoded {
            for target in ins.branch_targets().unwrap() {
                assert!(starts.contains(&target));
            }
        }
    }

    #[test]
    fn simple_interpolation_matches_native_fixture() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/format_context.native.bin"
        ))
        .unwrap();
        let ast = dm_syntax::parse(include_str!(
            "../../../fixtures/translation/format_context.dm"
        ));
        for name in [
            "format_context_00",
            "format_context_03",
            "format_context_57",
            "format_context_58",
            "format_context_59",
            "format_context_128",
            "format_context_129",
        ] {
            let item = ast
                .items
                .iter()
                .find(|item| item.header.starts_with(&format!("/proc/{name}(")))
                .unwrap();
            let compiled = compile_simple_proc_with_params(&item.children, &["X".into()]).unwrap();
            let mut ledger = Ledger::default();
            for key in &compiled.strings {
                let id = native
                    .strings
                    .iter()
                    .position(|entry| entry.data == compiled.string_bytes(key))
                    .unwrap();
                ledger
                    .bind(crate::Symbol::new(Table::String, key), id as u32)
                    .unwrap();
            }
            let linked = link_proc(&compiled.code, &ledger).unwrap();
            let id = native
                .procs
                .iter()
                .position(|proc| {
                    native
                        .string(proc.strings[0])
                        .is_some_and(|path| path.ends_with(name.as_bytes()))
                })
                .unwrap();
            assert_eq!(linked.words, native.proc_code_words(id).unwrap(), "{name}");
        }
    }

    #[test]
    fn multiple_interpolations_keep_order_and_template_bytes() {
        let ast = dm_syntax::parse("/proc/text(x,y)\n  return \"A [x] B [y]\"\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["x".into(), "y".into()])
                .unwrap();
        let key = compiled
            .strings
            .iter()
            .find(|key| compiled.format_templates.contains_key(*key))
            .unwrap();
        assert_eq!(compiled.string_bytes(key), b"A \xff\x01 B \xff\x01");
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, key), 5)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(decoded
            .iter()
            .any(|ins| ins.opcode == 2 && ins.operands == [5, 2]));
    }

    #[test]
    fn control_only_string_preserves_binary_marker() {
        let ast = dm_syntax::parse("/proc/test()\n  return \"\\proper K10\"\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let key = compiled.strings.first().unwrap();
        assert_eq!(compiled.string_bytes(key), b"\xff\x15K10");
    }

    #[test]
    fn literal_parameter_defaults_match_native_prologue() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/translation/argument_defaults.native.bin"
        ))
        .unwrap();
        let proc_id = native
            .procs
            .iter()
            .position(|proc| {
                native.string(proc.strings[0]) == Some(b"/proc/default_arg_probe".as_slice())
            })
            .unwrap();
        let class_id = native
            .classes
            .iter()
            .position(|class| native.string(class.path_string_id()) == Some(b"/obj".as_slice()))
            .unwrap();
        let string_id = native
            .strings
            .iter()
            .position(|string| string.data == b"hi")
            .unwrap();
        let ast = dm_syntax::parse("/proc/test(a,b,c,d)\n  return a\n");
        let bindings = LowerBindings {
            parameters: vec!["a".into(), "b".into(), "c".into(), "d".into()],
            parameter_defaults: vec![
                Some("5".into()),
                Some("\"hi\"".into()),
                Some("list(1, 2)".into()),
                Some("/obj".into()),
            ],
            ..LowerBindings::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::String, "hi"), string_id as u32)
            .unwrap();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/obj"), class_id as u32)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(linked.words, native.proc_code_words(proc_id).unwrap());
    }

    #[test]
    fn nested_list_iterators_save_and_restore_outer_state() {
        let ast = dm_syntax::parse("/proc/test(L)\n  for(var/outer in L)\n    for(var/inner in L)\n      if(inner)\n        break\n  return null\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert_eq!(
            decoded
                .iter()
                .filter(|instruction| instruction.opcode == opcode::ITER_PUSH)
                .count(),
            1
        );
        assert_eq!(
            decoded
                .iter()
                .filter(|instruction| instruction.opcode == opcode::ITER_POP)
                .count(),
            1
        );
    }
    #[test]
    fn typed_null_global_member_bypasses_receiver() {
        let ast = dm_syntax::parse("/proc/test()\n    GLOB.shared = 9\n    return GLOB.shared\n");
        let shared = SharedLowerBindings {
            member_globals: HashMap::from([(
                "/datum/base".into(),
                HashMap::from([("shared".into(), "shared_slot".into())]),
            )]),
            parent_types: HashMap::from([("/datum/child".into(), "/datum/base".into())]),
            ..Default::default()
        };
        let bindings = LowerBindings {
            global_types: HashMap::from([("GLOB".into(), "/datum/child".into())]),
            shared: Some(Arc::new(shared)),
            ..Default::default()
        };
        let compiled =
            compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Variable, "shared_slot"), 68)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        assert_eq!(
            linked.words,
            [0x50, 9, 0x34, 0xffdb, 68, 0x33, 0xffdb, 68, 0x12, 0]
        );
    }
    #[test]
    fn computed_global_member_rejects_untyped_instance_collision() {
        let ast = dm_syntax::parse("/proc/test()\n    return get_holder().shared\n");
        for collision in [false, true] {
            let mut shared = SharedLowerBindings {
                member_globals: HashMap::from([(
                    "/datum/base".into(),
                    HashMap::from([("shared".into(), "shared_slot".into())]),
                )]),
                known_member_fields: HashMap::from([(
                    "/datum/base".into(),
                    BTreeSet::from(["shared".into()]),
                )]),
                ..Default::default()
            };
            if collision {
                shared
                    .known_member_fields
                    .insert("/datum/other".into(), BTreeSet::from(["shared".into()]));
            }
            let bindings = LowerBindings {
                global_procs: BTreeSet::from(["get_holder".into()]),
                shared: Some(Arc::new(shared)),
                ..Default::default()
            };
            let compiled =
                compile_simple_proc_with_bindings(&ast.items[0].children, &bindings).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Proc, "/proc/get_holder"), 1)
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::Variable, "shared_slot"), 67)
                .unwrap();
            ledger
                .bind(crate::Symbol::new(Table::String, "shared"), 437)
                .unwrap();
            let words = link_proc(&compiled.code, &ledger).unwrap().words;
            if collision {
                assert_eq!(words, [0x30, 0, 1, 0x34, 0xffd8, 0x33, 437, 0x12, 0]);
            } else {
                assert_eq!(words, [0x30, 0, 1, 0x34, 0xffd8, 0x33, 0xffdb, 67, 0x12, 0]);
            }
        }
    }
    #[test]
    fn initializerless_local_inside_loop_resets_each_iteration() {
        let ast = dm_syntax::parse("/proc/test()\n    while(1)\n        var/datum/best\n        best = src\n        break\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let words = link_proc(&compiled.code, &Ledger::default()).unwrap().words;
        assert!(words
            .windows(6)
            .any(|window| window == [0x60, 0, 0, 0x34, 0xffda, 0]));
    }
    #[test]
    fn break_inside_switch_exits_enclosing_loop() {
        let ast = dm_syntax::parse("/proc/test()\n    while(1)\n        switch(1)\n            if(1)\n                break\n    return 7\n");
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let linked = link_proc(&compiled.code, &Ledger::default()).unwrap();
        let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
        let loop_exit = decoded
            .iter()
            .find(|instruction| instruction.opcode == opcode::JZ)
            .unwrap()
            .operands[0];
        assert!(decoded
            .iter()
            .filter(|instruction| instruction.opcode == opcode::JMP)
            .any(|instruction| instruction.operands[0] == loop_exit));
    }
    #[test]
    fn typed_obj_iterator_filters_subtypes_after_domain_mask() {
        let ast = dm_syntax::parse(
            "/proc/test()\n    for(var/obj/firedoor/F in src)\n        return F\n",
        );
        let compiled = compile_simple_proc(&ast.items[0].children).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/obj/firedoor"), 1)
            .unwrap();
        let linked = link_proc(&compiled.code, &ledger).unwrap();
        let instructions = byond_dmb::bytecode::decode(&linked.words).unwrap();
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == 0x7d));
        assert!(instructions
            .iter()
            .any(|instruction| instruction.opcode == opcode::ITER_LOAD
                && instruction.operands == [5, 2]));
    }
    #[test]
    fn locate_in_returns_object_instead_of_membership_boolean() {
        let ast = dm_syntax::parse("/proc/test(L)\n    return locate(/datum/coil) in L\n");
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
        let mut ledger = Ledger::default();
        ledger
            .bind(crate::Symbol::new(Table::Class, "/datum/coil"), 0)
            .unwrap();
        let words = link_proc(&compiled.code, &ledger).unwrap().words;
        assert_eq!(words, [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x12, 0]);
    }

    #[test]
    fn pick_prob_syntax_uses_numeric_weight_without_probability_call() {
        for (bare, sugar) in [("1", "prob(1)"), ("weight", "prob(weight)")] {
            let compile = |weight: &str| {
                let ast = dm_syntax::parse(&format!(
                    "/proc/test(weight)\n    return pick({weight};7, {weight};9)\n"
                ));
                let compiled =
                    compile_simple_proc_with_params(&ast.items[0].children, &["weight".into()])
                        .unwrap();
                link_proc(&compiled.code, &Ledger::default()).unwrap().words
            };
            assert_eq!(compile(bare), compile(sugar));
        }
    }

    #[test]
    fn negation_wraps_locate_in_clause_only_without_parentheses() {
        let compile = |expression: &str| {
            let ast = dm_syntax::parse(&format!("/proc/test(L)\n    return {expression}\n"));
            let compiled =
                compile_simple_proc_with_params(&ast.items[0].children, &["L".into()]).unwrap();
            let mut ledger = Ledger::default();
            ledger
                .bind(crate::Symbol::new(Table::Class, "/datum/coil"), 0)
                .unwrap();
            link_proc(&compiled.code, &ledger).unwrap().words
        };
        assert_eq!(
            compile("!locate(/datum/coil) in L"),
            [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x0e, 0x12, 0]
        );
        assert_eq!(
            compile("!!locate(/datum/coil) in L"),
            [0x60, 32, 0, 0x33, 0xffd9, 0, 0x97, 0x0e, 0x0e, 0x12, 0]
        );
        assert_eq!(
            compile("(!locate(/datum/coil)) in L"),
            [0x33, 0xffd9, 0, 0x60, 32, 0, 0x5b, 0x0e, 0xa9, 5, 0x36, 0x12, 0]
        );
        assert!(!compile("!1 in list(2)").contains(&0x97));
    }

    #[test]
    fn numeric_range_binding_matches_native_iteration_state() {
        let source = "/proc/test(low, high)\n    var/i = 99\n    for(i in low to high)\n        i += 10\n    return i\n";
        let ast = dm_syntax::parse(source);
        let compiled =
            compile_simple_proc_with_params(&ast.items[0].children, &["low".into(), "high".into()])
                .unwrap();
        let words = link_proc(&compiled.code, &Ledger::default()).unwrap().words;
        assert_eq!(
            words,
            [
                0x50, 99, 0x34, 0xffda, 0, 0x33, 0xffd9, 0, 0x33, 0xffd9, 1, 0xfc, 0xfd, 23,
                0xffda, 0, 0x50, 10, 0x45, 0xffda, 0, 0xf8, 12, 0xfb, 2, 0x33, 0xffda, 0, 0x12, 0
            ]
        );
    }
}
