//! Strict DM type contracts over the OpenDream export.
//!
//! This pass deliberately reports missing evidence. In particular, `unknown`
//! is not a subtype of every declared type.
use crate::contracts::{Contract, Visibility};
use crate::symbols::{declared_type, Symbols};
use crate::Finding;
use serde::Deserialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::io::{self, BufRead, Cursor, Seek, SeekFrom};
use std::path::Path;
use std::time::{Duration, Instant};

const STALE_REFERENCES: &str = "\0dm_health_stale_references";
const FLOW_ORIGIN_PREFIX: &str = "\0dm_health_unknown_flow:";

thread_local! {
    static PROFILE_WRITE_PROC: std::cell::RefCell<Option<String>> = const { std::cell::RefCell::new(None) };
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Ty {
    Unknown,
    NonNullUnknown,
    Null,
    Num,
    Text,
    Primitive(String),
    Path(String),
    EmptyList,
    EmptyAlist,
    List(Box<Ty>),
    Assoc(Box<Ty>, Box<Ty>),
    Alist(Box<Ty>, Box<Ty>),
    Record(BTreeMap<String, (Ty, bool)>),
    OneOf(Vec<Ty>),
    TypePath(String),
    Nullable(Box<Ty>),
    Void,
}

impl Ty {
    fn parse(raw: &str) -> Self {
        let raw = raw.trim().trim_matches('"');
        if let Some(inner) = raw.strip_suffix('?') {
            return Self::Nullable(Box::new(Self::parse(inner)));
        }
        if let Some(inner) = raw.strip_prefix("list<").and_then(|s| s.strip_suffix('>')) {
            return Self::List(Box::new(Self::parse(inner)));
        }
        if let Some(inner) = raw.strip_prefix("assoc<").and_then(|s| s.strip_suffix('>')) {
            if let Some((key, value)) = split_generic(inner) {
                return Self::Assoc(Box::new(Self::parse(key)), Box::new(Self::parse(value)));
            }
        }
        if let Some(inner) = raw.strip_prefix("alist<").and_then(|s| s.strip_suffix('>')) {
            if let Some((key, value)) = split_generic(inner) {
                return Self::Alist(Box::new(Self::parse(key)), Box::new(Self::parse(value)));
            }
        }
        if let Some(inner) = raw
            .strip_prefix("record<")
            .and_then(|s| s.strip_suffix('>'))
        {
            let mut fields = BTreeMap::new();
            if inner.trim().is_empty() {
                return Self::Record(fields);
            }
            let mut rest = inner;
            loop {
                let (entry, next) = match split_generic(rest) {
                    Some((entry, next)) => (entry, Some(next)),
                    None => (rest, None),
                };
                let Some((name, value)) = entry.trim().split_once(':') else {
                    return Self::Unknown;
                };
                let name = name.trim();
                let optional = name.ends_with('?');
                let name = name.strip_suffix('?').unwrap_or(name);
                if name.is_empty()
                    || !name
                        .chars()
                        .next()
                        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
                    || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
                    || value.trim().is_empty()
                    || fields
                        .insert(name.into(), (Self::parse(value), optional))
                        .is_some()
                {
                    return Self::Unknown;
                }
                let Some(next) = next else { break };
                rest = next;
            }
            return Self::Record(fields);
        }
        if let Some(inner) = raw.strip_prefix("oneof<").and_then(|s| s.strip_suffix('>')) {
            let mut choices = Vec::new();
            let mut rest = inner;
            loop {
                let (choice, next) = match split_generic(rest) {
                    Some((choice, next)) => (choice, Some(next)),
                    None => (rest, None),
                };
                let ty = Self::parse(choice);
                if choice.trim().is_empty() || ty == Self::Unknown || choices.contains(&ty) {
                    return Self::Unknown;
                }
                choices.push(ty);
                let Some(next) = next else { break };
                rest = next;
            }
            return if choices.len() >= 2 {
                Self::OneOf(choices)
            } else {
                Self::Unknown
            };
        }
        if let Some(inner) = raw.strip_prefix("merge<").and_then(|s| s.strip_suffix('>')) {
            let Some((left, right)) = split_generic(inner) else {
                return Self::Unknown;
            };
            let (Self::Record(mut left), Self::Record(right)) =
                (Self::parse(left), Self::parse(right))
            else {
                return Self::Unknown;
            };
            if right.keys().any(|name| left.contains_key(name)) {
                return Self::Unknown;
            }
            left.extend(right);
            return Self::Record(left);
        }
        if let Some(inner) = raw
            .strip_prefix("typepath<")
            .and_then(|s| s.strip_suffix('>'))
        {
            return Self::TypePath(inner.into());
        }
        match raw {
            "num" => Self::Num,
            "text" => Self::Text,
            "file" | "sound" | "icon" => Self::Primitive(raw.into()),
            "null" => Self::Null,
            "void" => Self::Void,
            "/list" | "list" => Self::List(Box::new(Self::Unknown)),
            "/alist" | "alist" => Self::Alist(Box::new(Self::Unknown), Box::new(Self::Unknown)),
            "unknown" | "anything" | "" => Self::Unknown,
            _ if raw.starts_with('/') => Self::Path(raw.into()),
            _ => Self::Unknown,
        }
    }

    fn label(&self) -> String {
        match self {
            Self::Unknown => "unknown".into(),
            Self::NonNullUnknown => "unknown (non-null)".into(),
            Self::Null => "null".into(),
            Self::Num => "num".into(),
            Self::Text => "text".into(),
            Self::Primitive(p) => p.clone(),
            Self::Path(p) => p.clone(),
            Self::EmptyList => "empty list (element type unknown)".into(),
            Self::EmptyAlist => "empty alist (key/value types unknown)".into(),
            Self::List(v) => format!("list<{}>", v.label()),
            Self::Assoc(k, v) => format!("assoc<{},{}>", k.label(), v.label()),
            Self::Alist(k, v) => format!("alist<{},{}>", k.label(), v.label()),
            Self::Record(fields) => format!(
                "record<{}>",
                fields
                    .iter()
                    .map(|(name, (ty, optional))| format!(
                        "{name}{}:{}",
                        if *optional { "?" } else { "" },
                        ty.label()
                    ))
                    .collect::<Vec<_>>()
                    .join(",")
            ),
            Self::OneOf(choices) => format!(
                "oneof<{}>",
                choices
                    .iter()
                    .map(Self::label)
                    .collect::<Vec<_>>()
                    .join(",")
            ),
            Self::TypePath(p) => format!("typepath<{p}>"),
            Self::Nullable(v) => format!("{}?", v.label()),
            Self::Void => "void".into(),
        }
    }

    fn may_be_null(&self) -> bool {
        matches!(self, Self::Unknown | Self::Null | Self::Nullable(_))
    }

    fn is_precise(&self) -> bool {
        match self {
            Self::Unknown
            | Self::NonNullUnknown
            | Self::Null
            | Self::EmptyList
            | Self::EmptyAlist => false,
            Self::List(value) | Self::Nullable(value) => value.is_precise(),
            Self::Assoc(key, value) | Self::Alist(key, value) => {
                key.is_precise() && value.is_precise()
            }
            Self::Record(fields) => fields.values().all(|(ty, _)| ty.is_precise()),
            Self::OneOf(choices) => choices.iter().all(Self::is_precise),
            _ => true,
        }
    }

    fn has_unknown(&self) -> bool {
        match self {
            Self::Unknown | Self::NonNullUnknown | Self::EmptyList | Self::EmptyAlist => true,
            Self::List(value) | Self::Nullable(value) => value.has_unknown(),
            Self::Assoc(key, value) | Self::Alist(key, value) => {
                key.has_unknown() || value.has_unknown()
            }
            Self::Record(fields) => fields.values().any(|(ty, _)| ty.has_unknown()),
            Self::OneOf(choices) => choices.iter().any(Self::has_unknown),
            _ => false,
        }
    }

    fn nonnull(&self) -> Self {
        if let Self::Nullable(inner) = self {
            inner.nonnull()
        } else if self == &Self::Unknown {
            Self::NonNullUnknown
        } else {
            self.clone()
        }
    }

    fn accepts(&self, value: &Self, symbols: &Symbols) -> bool {
        if let Self::Nullable(inner) = self {
            return match value {
                Self::Null => true,
                Self::Nullable(actual) => inner.accepts(actual, symbols),
                other => inner.accepts(other, symbols),
            };
        }
        if matches!(self, Self::Unknown | Self::NonNullUnknown)
            || matches!(value, Self::Unknown | Self::NonNullUnknown)
        {
            return false;
        }
        match (self, value) {
            (Self::OneOf(expected), Self::OneOf(actual)) => actual.iter().all(|actual| {
                expected
                    .iter()
                    .any(|expected| expected.accepts(actual, symbols))
            }),
            (Self::OneOf(choices), value) => {
                choices.iter().any(|choice| choice.accepts(value, symbols))
            }
            (Self::Void, Self::Null) => true,
            (Self::Path(expected), Self::Path(actual)) => symbols.is_subtype(actual, expected),
            (Self::Primitive(expected), Self::Primitive(actual)) if expected == "file" => {
                matches!(actual.as_str(), "file" | "icon" | "sound")
            }
            (Self::List(_) | Self::Assoc(_, _), Self::EmptyList) => true,
            (Self::Alist(_, _), Self::EmptyAlist) => true,
            (Self::Record(fields), Self::EmptyList) => {
                fields.values().all(|(_, optional)| *optional)
            }
            (Self::TypePath(expected), Self::TypePath(actual)) => {
                if expected.contains("/proc") || expected.contains("/verb") {
                    actual == expected || actual.starts_with(&format!("{expected}/"))
                } else {
                    symbols.is_subtype(actual, expected)
                }
            }
            (Self::List(expected), Self::List(actual)) => {
                matches!(**expected, Self::Unknown) || expected == actual
            }
            (Self::List(expected), Self::Assoc(_, _)) if matches!(**expected, Self::Unknown) => {
                true
            }
            (Self::List(expected), Self::Alist(_, _)) if matches!(**expected, Self::Unknown) => {
                true
            }
            (Self::List(expected), Self::Record(_)) if matches!(**expected, Self::Unknown) => true,
            (Self::Assoc(a, b), Self::Assoc(c, d)) => a == c && b == d,
            (Self::Alist(a, b), Self::Alist(c, d)) => a == c && b == d,
            _ => self == value,
        }
    }

    fn join(&self, other: &Self, symbols: &Symbols) -> Self {
        if self == other {
            return self.clone();
        }
        if *self == Self::Unknown || *other == Self::Unknown {
            return Self::Unknown;
        }
        if *self == Self::NonNullUnknown || *other == Self::NonNullUnknown {
            return if self.may_be_null() || other.may_be_null() {
                Self::Unknown
            } else {
                Self::NonNullUnknown
            };
        }
        if *self == Self::Null {
            return Self::Nullable(Box::new(other.nonnull()));
        }
        if *other == Self::Null {
            return Self::Nullable(Box::new(self.nonnull()));
        }
        if matches!(self, Self::Nullable(_)) || matches!(other, Self::Nullable(_)) {
            let joined = self.nonnull().join(&other.nonnull(), symbols);
            return Self::Nullable(Box::new(joined));
        }
        match (self, other) {
            (Self::EmptyList, Self::List(_) | Self::Assoc(_, _)) => other.clone(),
            (Self::List(_) | Self::Assoc(_, _), Self::EmptyList) => self.clone(),
            (Self::EmptyAlist, Self::Alist(_, _)) => other.clone(),
            (Self::Alist(_, _), Self::EmptyAlist) => self.clone(),
            (Self::Path(a), Self::Path(b)) => symbols
                .common_ancestor(a, b)
                .map(Self::Path)
                .unwrap_or(Self::Unknown),
            (Self::Primitive(a), Self::Primitive(b))
                if matches!(a.as_str(), "file" | "icon" | "sound")
                    && matches!(b.as_str(), "file" | "icon" | "sound") =>
            {
                Self::Primitive("file".into())
            }
            (Self::TypePath(a), Self::TypePath(b)) => {
                if a.contains("/proc/") && b.contains("/proc/") {
                    let common = a
                        .split('/')
                        .zip(b.split('/'))
                        .take_while(|(left, right)| left == right)
                        .map(|(part, _)| part)
                        .collect::<Vec<_>>()
                        .join("/");
                    if common.contains("/proc") {
                        Self::TypePath(common)
                    } else {
                        Self::Unknown
                    }
                } else {
                    symbols
                        .common_ancestor(a, b)
                        .map(Self::TypePath)
                        .unwrap_or(Self::Unknown)
                }
            }
            (Self::List(a), Self::List(b)) => Self::List(Box::new(a.join(b, symbols))),
            (Self::Assoc(a, b), Self::Assoc(c, d)) => {
                Self::Assoc(Box::new(a.join(c, symbols)), Box::new(b.join(d, symbols)))
            }
            (Self::Alist(a, b), Self::Alist(c, d)) => {
                Self::Alist(Box::new(a.join(c, symbols)), Box::new(b.join(d, symbols)))
            }
            (Self::Record(left), Self::Record(right)) => {
                let mut fields = left.clone();
                for (name, (right_ty, right_optional)) in right {
                    if let Some((left_ty, left_optional)) = fields.get_mut(name) {
                        *left_ty = left_ty.join(right_ty, symbols);
                        *left_optional |= right_optional;
                    } else {
                        fields.insert(name.clone(), (right_ty.clone(), true));
                    }
                }
                for (name, (_, optional)) in &mut fields {
                    if !right.contains_key(name) {
                        *optional = true;
                    }
                }
                Self::Record(fields)
            }
            (Self::EmptyList, Self::Record(fields)) | (Self::Record(fields), Self::EmptyList) => {
                Self::Record(
                    fields
                        .iter()
                        .map(|(name, (ty, _))| (name.clone(), (ty.clone(), true)))
                        .collect(),
                )
            }
            _ => Self::Unknown,
        }
    }
}

fn split_generic(input: &str) -> Option<(&str, &str)> {
    let mut depth = 0usize;
    for (index, ch) in input.char_indices() {
        match ch {
            '<' => depth += 1,
            '>' => depth = depth.saturating_sub(1),
            ',' if depth == 0 => return Some((&input[..index], &input[index + 1..])),
            _ => {}
        }
    }
    None
}

fn f<'a>(node: &'a Value, name: &str) -> &'a Value {
    &node["fields"][name]
}

fn numeric_parameter_uses(
    node: &Value,
    parameters: &HashMap<String, usize>,
    found: &mut Vec<usize>,
) {
    if kind(node) == "DMASTProcBlockInner" {
        for statement in f(node, "Statements").as_array().into_iter().flatten() {
            numeric_parameter_uses(statement, parameters, found);
            if kind(statement) == "DMASTProcStatementReturn" {
                break;
            }
        }
        return;
    }
    let operands: &[&str] = match kind(node) {
        "DMASTSubtract" | "DMASTMultiply" | "DMASTDivide" | "DMASTModulus" | "DMASTPower"
        | "DMASTLeftShift" | "DMASTRightShift" | "DMASTBinaryAnd" | "DMASTBinaryOr"
        | "DMASTBinaryXor" => &["LHS", "RHS"],
        "DMASTBinaryNot" | "DMASTNegate" | "DMASTPreIncrement" | "DMASTPostIncrement"
        | "DMASTPreDecrement" | "DMASTPostDecrement" => &["Value"],
        _ => &[],
    };
    for operand in operands {
        let value = f(node, operand);
        if kind(value) == "DMASTIdentifier" {
            if let Some(index) = f(value, "Identifier")
                .as_str()
                .and_then(|name| parameters.get(name))
            {
                found.push(*index);
            }
        }
    }
    if let Some(fields) = node["fields"].as_object() {
        for child in fields.values() {
            if let Some(items) = child.as_array() {
                for item in items {
                    if item.is_object() {
                        numeric_parameter_uses(item, parameters, found);
                    }
                }
            } else if child.is_object() {
                numeric_parameter_uses(child, parameters, found);
            }
        }
    }
}

fn resource_type(path: &str) -> Ty {
    let extension = path.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
    let kind = match extension.as_str() {
        "dmi" | "bmp" | "png" | "jpg" | "jpeg" | "gif" => "icon",
        "wav" | "ogg" | "mp3" | "raw" | "wma" | "aiff" | "mid" | "midi" | "mod" | "it" | "s3m"
        | "xm" | "oxm" => "sound",
        _ => "file",
    };
    Ty::Primitive(kind.into())
}

fn kind(node: &Value) -> &str {
    node["kind"].as_str().unwrap_or("")
}

fn simple_statements(block: &Value) -> Option<&Vec<Value>> {
    if kind(block) != "DMASTProcBlockInner"
        || !f(block, "SetStatements")
            .as_array()
            .is_none_or(Vec::is_empty)
    {
        return None;
    }
    f(block, "Statements").as_array()
}

fn simple_block_returns(block: &Value) -> bool {
    let Some(last) = simple_statements(block).and_then(|statements| statements.last()) else {
        return false;
    };
    match kind(last) {
        "DMASTProcStatementReturn" => true,
        "DMASTProcStatementIf" => {
            simple_block_returns(f(last, "Body")) && simple_block_returns(f(last, "ElseBody"))
        }
        _ => false,
    }
}

fn identifier_is(node: &Value, name: &str) -> bool {
    kind(node) == "DMASTIdentifier" && f(node, "Identifier").as_str() == Some(name)
}

fn record_index_is(node: &Value, receiver: &str, key: &str) -> bool {
    if kind(node) != "DMASTDereference" {
        return false;
    }
    let base = f(node, "Expression");
    let matching_receiver = if receiver.is_empty() {
        kind(base) == "DMASTCallableSelf"
    } else {
        identifier_is(base, receiver)
    };
    let Some(operations) = f(node, "Operations").as_array() else {
        return false;
    };
    matching_receiver
        && operations.len() == 1
        && kind(&operations[0]) == "IndexOperation"
        && f(&operations[0], "Safe").as_bool() != Some(true)
        && identifier_is(f(&operations[0], "Index"), key)
}

fn iterator_declaration(node: &Value) -> Option<(String, Ty)> {
    if kind(node) != "DMASTVarDeclExpression" {
        return None;
    }
    let path = f(f(node, "DeclPath"), "Path")
        .as_str()?
        .strip_prefix("var/")?;
    let (type_path, name) = match path.rsplit_once('/') {
        Some((ty, name)) => (format!("/{ty}"), name),
        None => (String::new(), path),
    };
    if name.is_empty()
        || !name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || ch == '_')
    {
        return None;
    }
    let ty = if type_path.is_empty() {
        Ty::Unknown
    } else {
        Ty::parse(&crate::symbols::declared_type(Some(&type_path), None))
    };
    Some((name.into(), ty))
}

fn collect_local_names(node: &Value, names: &mut HashSet<String>) {
    if kind(node) == "DMASTProcStatementVarDeclaration" {
        if let Some(name) = f(node, "Name").as_str() {
            names.insert(name.into());
        }
    } else if let Some((name, _)) = iterator_declaration(node) {
        names.insert(name);
    }
    if let Some(fields) = node["fields"].as_object() {
        for value in fields.values() {
            if let Some(items) = value.as_array() {
                for item in items {
                    if item.is_object() {
                        collect_local_names(item, names);
                    }
                }
            } else if value.is_object() {
                collect_local_names(value, names);
            }
        }
    }
}

#[derive(Default)]
struct LocalWrites<'a> {
    declarations: Vec<&'a Value>,
    writes: HashMap<String, Vec<&'a Value>>,
    write_sites: HashMap<String, Vec<(String, usize)>>,
    unsafe_writes: HashSet<String>,
    repeated: HashSet<String>,
    seen: HashSet<String>,
}

#[derive(Clone, Default)]
struct LocalTypeFlow {
    facts: HashMap<String, Ty>,
    assigned: HashSet<String>,
}

fn collect_local_writes<'a>(node: &'a Value, result: &mut LocalWrites<'a>) {
    if kind(node) == "DMASTProcStatementVarDeclaration" {
        let name = f(node, "Name").as_str();
        if let Some(name) = name {
            result.declarations.push(node);
            if !result.seen.insert(name.into()) {
                result.repeated.insert(name.into());
            }
        }
    } else if let Some((name, _)) = iterator_declaration(node) {
        if !result.seen.insert(name.clone()) {
            result.repeated.insert(name.clone());
        }
    }
    let lhs = f(node, "LHS");
    if kind(node) == "DMASTAssign" && kind(lhs) == "DMASTIdentifier" {
        if let Some(name) = f(lhs, "Identifier").as_str() {
            if !result.seen.contains(name) {
                result.unsafe_writes.insert(name.into());
            }
            result
                .writes
                .entry(name.into())
                .or_default()
                .push(f(node, "RHS"));
            result
                .write_sites
                .entry(name.into())
                .or_default()
                .push(source(node));
        }
    } else if (kind(node).ends_with("Assign")
        || matches!(kind(node), "DMASTAppend" | "DMASTRemove"))
        && kind(lhs) == "DMASTIdentifier"
    {
        if let Some(name) = f(lhs, "Identifier").as_str() {
            result.unsafe_writes.insert(name.into());
        }
    } else if matches!(
        kind(node),
        "DMASTPreIncrement" | "DMASTPostIncrement" | "DMASTPreDecrement" | "DMASTPostDecrement"
    ) {
        for field in ["Expression", "Value"] {
            let target = f(node, field);
            if kind(target) == "DMASTIdentifier" {
                if let Some(name) = f(target, "Identifier").as_str() {
                    result.unsafe_writes.insert(name.into());
                }
            }
        }
    }
    if let Some(fields) = node["fields"].as_object() {
        for value in fields.values() {
            if let Some(items) = value.as_array() {
                for item in items {
                    if item.is_object() {
                        collect_local_writes(item, result);
                    }
                }
            } else if value.is_object() {
                collect_local_writes(value, result);
            }
        }
    }
}

fn contains_identifier(node: &Value) -> bool {
    if kind(node) == "DMASTIdentifier" {
        return true;
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|value| {
            if let Some(items) = value.as_array() {
                items.iter().any(contains_identifier)
            } else if value.is_object() {
                contains_identifier(value)
            } else {
                false
            }
        })
    })
}

fn contains_mutation(node: &Value) -> bool {
    if kind(node).ends_with("Assign")
        || matches!(
            kind(node),
            "DMASTAppend"
                | "DMASTRemove"
                | "DMASTPreIncrement"
                | "DMASTPostIncrement"
                | "DMASTPreDecrement"
                | "DMASTPostDecrement"
        )
    {
        return true;
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|value| {
            if let Some(items) = value.as_array() {
                items.iter().any(contains_mutation)
            } else if value.is_object() {
                contains_mutation(value)
            } else {
                false
            }
        })
    })
}

fn is_value_expression(name: &str) -> bool {
    name.starts_with("DMAST")
        && !name.ends_with("Assign")
        && !name.starts_with("DMASTProcStatement")
        && !name.starts_with("DMASTCallable")
        && !matches!(
            name,
            "DMASTProcBlockInner"
                | "DMASTCallParameter"
                | "DMASTPath"
                | "DMASTModifiedType"
                | "DMASTVarDeclExpression"
                | "DMASTSwitchCaseRange"
                | "DMASTCallableSelf"
                | "DMASTNullProcStatement"
        )
}

fn place(expr: &Value) -> Option<String> {
    match kind(expr) {
        "DMASTExpressionWrapped" => place(f(expr, "Value")),
        "DMASTIdentifier" => f(expr, "Identifier").as_str().map(str::to_owned),
        "DMASTDereference" => {
            let mut result = place(f(expr, "Expression"))?;
            for operation in f(expr, "Operations").as_array()?.iter() {
                match kind(operation) {
                    "FieldOperation" => {
                        result.push('.');
                        result.push_str(f(operation, "Identifier").as_str()?);
                    }
                    "IndexOperation" => {
                        result = indexed_place_key(&result, f(operation, "Index"))?;
                    }
                    _ => return None,
                }
            }
            Some(result)
        }
        _ => None,
    }
}

fn indexed_place_key(prefix: &str, index: &Value) -> Option<String> {
    if !matches!(kind(index), "DMASTConstantString" | "DMASTConstantInteger") {
        return None;
    }
    let literal = f(index, "Value");
    if literal.is_null() {
        return None;
    }
    let encoded = literal.to_string();
    (encoded.len() <= 128).then(|| format!("{prefix}.[{encoded}]"))
}

fn overwrite_place_fact(facts: &mut HashMap<String, Ty>, name: &str, value: Ty) {
    let prefix = format!("{name}.");
    facts.retain(|key, _| !key.starts_with(&prefix));
    facts.insert(name.into(), value);
}

fn constructor_literal_type(expr: &Value) -> Option<Ty> {
    match kind(expr) {
        "DMASTConstantInteger" | "DMASTConstantFloat" => Some(Ty::Num),
        "DMASTConstantString" => Some(Ty::Text),
        "DMASTConstantPath" => f(f(expr, "Value"), "Path")
            .as_str()
            .map(|path| Ty::TypePath(path.into())),
        _ => None,
    }
}

fn numeric_operand(ty: &Ty) -> bool {
    matches!(ty, Ty::Num | Ty::Null) || matches!(ty, Ty::Nullable(inner) if **inner == Ty::Num)
}

fn always_truthy_type(ty: &Ty) -> bool {
    // DM's only false values are null, numeric zero, and empty text. A
    // non-null datum, type path, or collection cannot short-circuit as false.
    matches!(
        ty,
        Ty::Path(_)
            | Ty::TypePath(_)
            | Ty::EmptyList
            | Ty::EmptyAlist
            | Ty::List(_)
            | Ty::Assoc(_, _)
            | Ty::Alist(_, _)
            | Ty::Record(_)
    )
}

fn literal_truthiness(expr: &Value) -> Option<bool> {
    match kind(expr) {
        "DMASTExpressionWrapped" => literal_truthiness(f(expr, "Value")),
        "DMASTConstantNull" => Some(false),
        "DMASTConstantInteger" | "DMASTConstantFloat" => {
            f(expr, "Value").as_f64().map(|value| value != 0.0)
        }
        "DMASTConstantString" => f(expr, "Value").as_str().map(|value| !value.is_empty()),
        _ => None,
    }
}

fn collection_field_type(receiver: &Ty, member: &str) -> Option<Ty> {
    if member == "len"
        && matches!(
            receiver,
            Ty::EmptyList
                | Ty::EmptyAlist
                | Ty::List(_)
                | Ty::Assoc(_, _)
                | Ty::Alist(_, _)
                | Ty::Record(_)
        )
    {
        Some(Ty::Num)
    } else {
        None
    }
}

fn contextual_new_type(expr: &Value, expected: &Ty) -> Option<Ty> {
    if kind(expr) != "DMASTNewInferred" {
        return None;
    }
    // OpenDream uses both null and [] for a constructor with no arguments.
    let empty_parameters = f(expr, "Parameters").is_null()
        || f(expr, "Parameters").as_array().is_some_and(Vec::is_empty);
    match expected.nonnull() {
        Ty::Path(path) => Some(Ty::Path(path)),
        Ty::List(_) if empty_parameters => Some(Ty::EmptyList),
        Ty::Alist(_, _) if empty_parameters => Some(Ty::EmptyAlist),
        _ => None,
    }
}

fn dimensional_list_type(dimensions: usize) -> Ty {
    if dimensions == 0 {
        return Ty::EmptyList;
    }
    if dimensions > 32 {
        return Ty::Unknown;
    }
    (0..dimensions).fold(Ty::Unknown, |inner, _| Ty::List(Box::new(inner)))
}

fn pure_constructor_condition(expr: &Value) -> bool {
    match kind(expr) {
        "DMASTConstantInteger" | "DMASTConstantFloat" | "DMASTConstantString" => true,
        "DMASTExpressionWrapped" | "DMASTNot" => pure_constructor_condition(f(expr, "Value")),
        "DMASTEqual"
        | "DMASTNotEqual"
        | "DMASTGreaterThan"
        | "DMASTLessThan"
        | "DMASTGreaterThanOrEqual"
        | "DMASTLessThanOrEqual"
        | "DMASTAnd"
        | "DMASTOr" => {
            pure_constructor_condition(f(expr, "LHS")) && pure_constructor_condition(f(expr, "RHS"))
        }
        _ => false,
    }
}

fn finite_literal_names(expr: &Value) -> Option<Vec<&str>> {
    match kind(expr) {
        "DMASTConstantString" => Some(vec![f(expr, "Value").as_str()?]),
        "DMASTExpressionWrapped" => finite_literal_names(f(expr, "Value")),
        "DMASTTernary" if !contains_unknown_effect(f(expr, "A")) => {
            let mut names = finite_literal_names(f(expr, "B"))?;
            for name in finite_literal_names(f(expr, "C"))? {
                if !names.contains(&name) {
                    names.push(name);
                }
            }
            (names.len() <= 8).then_some(names)
        }
        _ => None,
    }
}

fn constructible_datum_bound(path: &str, symbols: &Symbols) -> bool {
    let segments: Vec<_> = path.split('/').filter(|part| !part.is_empty()).collect();
    if segments.iter().any(|part| matches!(*part, "proc" | "verb")) {
        return false;
    }
    symbols.is_subtype(path, "/datum")
}

// Bit 1 is a path where the required field is still null; bit 2 is a path
// where a compatible literal has been written. Unknown effects invalidate the
// proof instead of being treated as a successful assignment.
fn constructor_paths(
    block: &Value,
    mut paths: u8,
    owner: &str,
    required: &str,
    required_type: &Ty,
    fields: &HashSet<(String, String)>,
    symbols: &Symbols,
) -> Option<u8> {
    for statement in f(block, "Statements").as_array()? {
        if paths == 0 {
            break;
        }
        match kind(statement) {
            "DMASTProcStatementExpression" => {
                let assignment = f(statement, "Expression");
                if kind(assignment) != "DMASTAssign" {
                    return None;
                }
                let target = place(f(assignment, "LHS"))?;
                let target = target.strip_prefix("src.").unwrap_or(&target);
                if target.contains('.') || !fields.contains(&(owner.into(), target.into())) {
                    return None;
                }
                let value = constructor_literal_type(f(assignment, "RHS"))?;
                if target == required {
                    if !required_type.accepts(&value, symbols) {
                        return None;
                    }
                    paths = 2;
                }
            }
            "DMASTProcStatementIf" => {
                if !pure_constructor_condition(f(statement, "Condition")) {
                    return None;
                }
                let yes = constructor_paths(
                    f(statement, "Body"),
                    paths,
                    owner,
                    required,
                    required_type,
                    fields,
                    symbols,
                )?;
                let no = if f(statement, "ElseBody").is_null() {
                    paths
                } else {
                    constructor_paths(
                        f(statement, "ElseBody"),
                        paths,
                        owner,
                        required,
                        required_type,
                        fields,
                        symbols,
                    )?
                };
                paths = yes | no;
            }
            "DMASTProcStatementReturn" => {
                if paths & 1 != 0 || !f(statement, "Value").is_null() {
                    return None;
                }
                paths = 0;
            }
            _ => return None,
        }
    }
    Some(paths)
}

fn seed_guard_facts(
    condition: &Value,
    vars: &mut HashMap<String, Ty>,
    checker: &Checker<'_>,
    owner: &str,
) {
    match kind(condition) {
        "DMASTNot" => seed_guard_facts(f(condition, "Value"), vars, checker, owner),
        "DMASTAnd" | "DMASTOr" => {
            seed_guard_facts(f(condition, "LHS"), vars, checker, owner);
            seed_guard_facts(f(condition, "RHS"), vars, checker, owner);
        }
        "DMASTIsNull" | "DMASTImplicitIsType" => {
            seed_place(f(condition, "Value"), vars, checker, owner)
        }
        "DMASTIsType" => seed_place(f(condition, "LHS"), vars, checker, owner),
        "DMASTEqual" | "DMASTNotEqual" => {
            seed_place(f(condition, "LHS"), vars, checker, owner);
            seed_place(f(condition, "RHS"), vars, checker, owner);
        }
        "DMASTProcCall" => {
            let name = f(f(condition, "Callable"), "Identifier")
                .as_str()
                .unwrap_or("");
            if (matches!(
                name,
                "isnull"
                    | "QDELETED"
                    | "islist"
                    | "isnum"
                    | "istext"
                    | "isarea"
                    | "ismob"
                    | "isobj"
                    | "isturf"
                    | "ismovable"
            ) && checked_unary_builtin(condition))
                || (name == "ispath" && checked_ispath_builtin(condition))
            {
                if let Some(argument) = f(condition, "Parameters")
                    .as_array()
                    .and_then(|args| args.first())
                {
                    seed_place(f(argument, "Value"), vars, checker, owner);
                }
            }
        }
        "DMASTIdentifier" | "DMASTDereference" => seed_place(condition, vars, checker, owner),
        _ => {}
    }
}

fn seed_place(expr: &Value, vars: &mut HashMap<String, Ty>, checker: &Checker<'_>, owner: &str) {
    if let Some(key) = place(expr) {
        if !vars.contains_key(&key) {
            let ty = checker.expression(expr, vars, owner);
            vars.insert(key, ty);
        }
    }
}

fn source(node: &Value) -> (String, usize) {
    (
        node["file"]
            .as_str()
            .unwrap_or("<unknown>")
            .replace('\\', "/"),
        node["line"].as_u64().unwrap_or(1) as usize,
    )
}

fn issue(node: &Value, rule: &'static str, message: String) -> Finding {
    let (path, line) = source(node);
    Finding {
        rule,
        path,
        line,
        severity: "error",
        message,
    }
}

fn annotation<'a>(
    contracts: &'a [Contract],
    owner: &str,
    member: &str,
    kind: Visibility,
    param: Option<&str>,
) -> Option<&'a Contract> {
    contracts.iter().rev().find(|c| {
        (c.owner == owner || (owner == "/datum/controller/global_vars" && c.owner == "GLOB"))
            && c.member == member
            && c.visibility == kind
            && c.parameter.as_deref() == param
    })
}

fn declared(raw: &Value, value_type: &Value) -> Ty {
    if raw.is_null() {
        if let Some(path) = value_type
            .as_str()
            .map(|v| v.trim_matches('"'))
            .and_then(|v| v.strip_prefix("path, "))
        {
            return Ty::TypePath(path.into());
        }
    }
    Ty::parse(&declared_type(raw.as_str(), value_type.as_str()))
}

fn builtin_field_type(owner: &str, name: &str) -> Option<Ty> {
    let ty = match (owner, name) {
        // OpenDream's standard declarations use `anything` for these engine
        // fields. Their runtime value domains are narrower than that export.
        ("/atom", "name") => Ty::Nullable(Box::new(Ty::Text)),
        ("/atom", "gender") => Ty::Nullable(Box::new(Ty::Text)),
        ("/atom", "dir" | "x" | "y" | "z" | "density" | "opacity") | ("/client", "dir") => Ty::Num,
        ("/datum", "type") => Ty::TypePath("/datum".into()),
        ("/client", "type") => Ty::TypePath("/client".into()),
        ("/world" | "/client", "view") => Ty::OneOf(vec![Ty::Num, Ty::Text]),
        (
            "/world",
            "time" | "realtime" | "timeofday" | "timezone" | "tick_lag" | "fps" | "cpu"
            | "tick_usage" | "map_cpu" | "maxx" | "maxy" | "maxz" | "icon_size" | "byond_version"
            | "byond_build" | "loop_checks" | "sleep_offline",
        ) => Ty::Num,
        ("/world", "port") => Ty::Nullable(Box::new(Ty::Num)),
        ("/world", "name" | "status") => Ty::Text,
        ("/world", "url" | "address" | "internet_address") => Ty::Nullable(Box::new(Ty::Text)),
        _ => return None,
    };
    Some(ty)
}

fn annotated_type(
    contracts: &[Contract],
    owner: &str,
    name: &str,
    kind: Visibility,
    parameter: Option<&str>,
) -> Option<Ty> {
    annotation(contracts, owner, name, kind, parameter)
        .and_then(|c| c.value.as_deref())
        .map(|raw| {
            expand_type_aliases(raw, contracts)
                .map(|expanded| Ty::parse(&expanded))
                .unwrap_or(Ty::Unknown)
        })
}

fn expand_type_aliases(raw: &str, contracts: &[Contract]) -> Option<String> {
    let mut aliases = HashMap::new();
    for contract in contracts
        .iter()
        .filter(|c| c.visibility == Visibility::TypeAlias)
    {
        let value = contract.value.as_deref()?;
        if aliases
            .insert(contract.member.as_str(), value)
            .is_some_and(|previous| previous != value)
        {
            return None;
        }
    }
    fn expand(
        raw: &str,
        aliases: &HashMap<&str, &str>,
        stack: &mut HashSet<String>,
    ) -> Option<String> {
        let mut output = String::new();
        let mut start = 0usize;
        let bytes = raw.as_bytes();
        let mut index = 0usize;
        while index < bytes.len() {
            if bytes[index] != b'@' {
                index += 1;
                continue;
            }
            output.push_str(&raw[start..index]);
            let alias_start = index + 1;
            let mut end = alias_start;
            while end < bytes.len() && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'_') {
                end += 1;
            }
            if end == alias_start {
                return None;
            }
            let name = &raw[alias_start..end];
            let definition = aliases.get(name)?;
            if !stack.insert(name.into()) {
                return None;
            }
            output.push_str(&expand(definition, aliases, stack)?);
            stack.remove(name);
            index = end;
            start = end;
        }
        output.push_str(&raw[start..]);
        Some(output)
    }
    expand(raw, &aliases, &mut HashSet::new())
}

fn nullable(contracts: &[Contract], owner: &str, name: &str, parameter: Option<&str>) -> bool {
    annotation(contracts, owner, name, Visibility::Nullable, parameter).is_some()
}

fn conflicting_contracts(
    contracts: &[Contract],
    owner: &str,
    member: &str,
    parameter: Option<&str>,
    type_kind: Visibility,
    field: bool,
) -> Vec<String> {
    let matching: Vec<_> = contracts
        .iter()
        .filter(|contract| {
            contract.owner == owner
                && contract.member == member
                && contract.parameter.as_deref() == parameter
        })
        .collect();
    let has = |kind| matching.iter().any(|contract| contract.visibility == kind);
    let mut conflicts = Vec::new();
    if has(Visibility::NonNull) && has(Visibility::Nullable) {
        conflicts.push("nonnull conflicts with nullable".into());
    }
    if field && has(Visibility::InitializedBy) && has(Visibility::Nullable) {
        conflicts.push("initialized-by conflicts with nullable".into());
    }
    if field {
        let phases: Vec<_> = matching
            .iter()
            .filter(|contract| contract.visibility == Visibility::InitializedBy)
            .filter_map(|contract| contract.value.as_deref())
            .collect();
        if phases.iter().skip(1).any(|phase| *phase != phases[0]) {
            conflicts.push("multiple different initialized-by phases target this field".into());
        }
    }
    let types: Vec<_> = matching
        .iter()
        .filter(|contract| contract.visibility == type_kind)
        .filter_map(|contract| contract.value.as_deref())
        .collect();
    if types.iter().skip(1).any(|ty| *ty != types[0]) {
        conflicts.push("multiple different type contracts target this declaration".into());
    }
    let has_optional_type = types.iter().any(|ty| {
        expand_type_aliases(ty, contracts)
            .is_some_and(|expanded| matches!(Ty::parse(&expanded), Ty::Nullable(_)))
    });
    if has(Visibility::NonNull) && has_optional_type {
        conflicts.push("nonnull conflicts with an optional type contract".into());
    }
    if field && has(Visibility::InitializedBy) && has_optional_type {
        conflicts.push("initialized-by conflicts with an optional type contract".into());
    }
    conflicts
}

fn with_nullable(ty: Ty, allowed: bool) -> Ty {
    if allowed && !ty.may_be_null() {
        Ty::Nullable(Box::new(ty))
    } else {
        ty
    }
}

#[derive(Clone, Debug)]
struct FieldInfo {
    ty: Ty,
    explicit_type: bool,
    evidence: Ty,
    origin: Value,
    nullable: bool,
    delayed: bool,
    phase: Option<String>,
    proved_initialization: bool,
    initially_null: bool,
    saw_unknown_write: bool,
    conflict: bool,
}

#[derive(Clone, Debug)]
struct ParamInfo {
    name: String,
    ty: Ty,
    has_default: bool,
    default_ty: Ty,
    inferred_from_calls: bool,
}

#[derive(Clone, Debug)]
struct Signature {
    parameters: Vec<ParamInfo>,
    result: Ty,
    result_required: bool,
    inferred_nullable_result: bool,
    path: String,
    line: usize,
}

fn standard_builtin_signature(signature: &Signature) -> bool {
    signature.path.rsplit('/').next() == Some("_Standard.dm")
}

// The ADMIN_VERB macro emits a client wrapper whose positional arguments are
// forwarded, after an injected client, to a subtype-specific implementation.
// Match its body instead of treating every similarly named proc as generated.
fn admin_verb_wrapper_target(name: &str, body: &Value) -> Option<String> {
    let suffix = name.strip_prefix("__avd_")?;
    let statements = f(body, "Statements").as_array()?;
    let [declaration, append, dispatch] = statements.as_slice() else {
        return None;
    };
    if kind(declaration) != "DMASTProcStatementVarDeclaration"
        || f(declaration, "Name").as_str() != Some("_verb_args")
    {
        return None;
    }
    let list = f(declaration, "Value");
    let values = f(list, "Values").as_array()?;
    if kind(list) != "DMASTList"
        || values.len() != 2
        || f(f(&values[0], "Value"), "Identifier").as_str() != Some("usr")
    {
        return None;
    }
    let path = f(f(f(&values[1], "Value"), "Value"), "Path").as_str()?;
    let target = format!("/datum/admin_verb/{suffix}");
    if path != target {
        return None;
    }
    let appended = f(append, "Expression");
    if kind(appended) != "DMASTAppend"
        || f(f(appended, "LHS"), "Identifier").as_str() != Some("_verb_args")
        || f(f(appended, "RHS"), "Identifier").as_str() != Some("args")
    {
        return None;
    }
    let call = f(dispatch, "Expression");
    if kind(call) != "DMASTDereference"
        || f(f(call, "Expression"), "Identifier").as_str() != Some("SSadmin_verbs")
    {
        return None;
    }
    let operations = f(call, "Operations").as_array()?;
    let [operation] = operations.as_slice() else {
        return None;
    };
    if kind(operation) != "CallOperation"
        || f(operation, "Identifier").as_str() != Some("dynamic_invoke_verb")
    {
        return None;
    }
    let parameters = f(operation, "Parameters").as_array()?;
    let [parameter] = parameters.as_slice() else {
        return None;
    };
    let packed = f(parameter, "Value");
    if kind(packed) != "DMASTProcCall"
        || f(f(packed, "Callable"), "Identifier").as_str() != Some("arglist")
    {
        return None;
    }
    let args = f(packed, "Parameters").as_array()?;
    if args.len() != 1 || f(f(&args[0], "Value"), "Identifier").as_str() != Some("_verb_args") {
        return None;
    }
    Some(target)
}

#[derive(Clone, Debug)]
struct ParamEvidence {
    ty: Ty,
    calls: usize,
    unresolved: usize,
    conflict: bool,
    constraint: Option<Ty>,
    constraint_sites: usize,
}

#[derive(Clone, Eq, PartialEq)]
struct Env {
    slots: HashMap<String, Ty>,
    facts: HashMap<String, Ty>,
    origins: HashMap<String, (String, usize)>,
    assigned: HashSet<String>,
    fresh_collections: HashSet<String>,
    result_fact: Ty,
}

#[derive(Default)]
struct LoopFlow {
    next: Option<Env>,
    breaks: Vec<Env>,
    continues: Vec<Env>,
}

impl Default for Env {
    fn default() -> Self {
        Self {
            slots: HashMap::new(),
            facts: HashMap::new(),
            origins: HashMap::new(),
            assigned: HashSet::new(),
            fresh_collections: HashSet::new(),
            result_fact: Ty::Null,
        }
    }
}

impl Env {
    fn record_references(&self, node: &Value) -> Vec<String> {
        if !self.facts.values().any(|ty| matches!(ty, Ty::Record(_))) {
            return Vec::new();
        }
        fn visit(node: &Value, facts: &HashMap<String, Ty>, found: &mut HashSet<String>) {
            fn scalar(ty: &Ty) -> bool {
                match ty {
                    Ty::Num
                    | Ty::Text
                    | Ty::Primitive(_)
                    | Ty::Path(_)
                    | Ty::TypePath(_)
                    | Ty::Null => true,
                    Ty::Nullable(inner) => scalar(inner),
                    _ => false,
                }
            }
            if kind(node) == "DMASTDereference" {
                let base = f(node, "Expression");
                if kind(base) == "DMASTIdentifier" {
                    if let Some(name) = f(base, "Identifier").as_str() {
                        if let Some(Ty::Record(fields)) = facts.get(name) {
                            let key = f(node, "Operations")
                                .as_array()
                                .and_then(|operations| operations.first())
                                .filter(|operation| kind(operation) == "IndexOperation")
                                .map(|operation| f(operation, "Index"))
                                .filter(|index| kind(index) == "DMASTConstantString")
                                .and_then(|index| f(index, "Value").as_str());
                            let scalar = key
                                .and_then(|key| fields.get(key))
                                .is_some_and(|(ty, _)| scalar(ty));
                            if !scalar {
                                found.insert(name.into());
                            }
                            return;
                        }
                    }
                }
            }
            if kind(node) == "DMASTLength" {
                return;
            }
            if kind(node) == "DMASTIdentifier" {
                if let Some(name) = f(node, "Identifier").as_str() {
                    if matches!(facts.get(name), Some(Ty::Record(_))) {
                        found.insert(name.into());
                    }
                }
            }
            if let Some(fields) = node["fields"].as_object() {
                for child in fields.values() {
                    if let Some(items) = child.as_array() {
                        for item in items {
                            if item.is_object() {
                                visit(item, facts, found);
                            }
                        }
                    } else if child.is_object() {
                        visit(child, facts, found);
                    }
                }
            }
        }
        let mut found = HashSet::new();
        visit(node, &self.facts, &mut found);
        found.into_iter().collect()
    }

    fn invalidate_record_aliases(&mut self, node: &Value, aliases: &[String]) {
        for name in aliases {
            self.record_fact_origin(name, &Ty::Unknown, node);
            overwrite_place_fact(&mut self.facts, name, Ty::Unknown);
        }
    }

    fn escape_fresh_references(&mut self, node: &Value) {
        let escaped: Vec<_> = self
            .fresh_collections
            .iter()
            .filter(|name| mentions_identifier(node, name))
            .cloned()
            .collect();
        for name in escaped {
            self.fresh_collections.remove(&name);
            self.record_fact_origin(&name, &Ty::Unknown, node);
            overwrite_place_fact(&mut self.facts, &name, Ty::Unknown);
        }
    }

    fn record_fact_origin(&mut self, name: &str, fact: &Ty, node: &Value) {
        let key = format!("{FLOW_ORIGIN_PREFIX}{name}");
        if fact.is_precise() || *fact == Ty::Null {
            self.origins.remove(&key);
        } else {
            self.origins.insert(key, source(node));
        }
    }

    fn invalidate_after(&mut self, expr: &Value) {
        let preserved = if contains_unknown_effect(expr) {
            self.fresh_collections
                .iter()
                .filter(|name| !fresh_reaches_unknown_effect(expr, name))
                .filter_map(|name| {
                    self.facts
                        .get(name)
                        .cloned()
                        .map(|fact| (name.clone(), fact))
                })
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        invalidate_after(expr, &mut self.facts);
        if contains_unknown_effect(expr) {
            self.origins.insert(STALE_REFERENCES.into(), source(expr));
            self.facts.retain(|name, _| {
                name == "src" || name == STALE_REFERENCES || self.slots.contains_key(name)
            });
            self.fresh_collections
                .retain(|name| preserved.iter().any(|(key, _)| key == name));
            for (name, fact) in preserved {
                self.facts.insert(name, fact);
            }
        }
    }

    fn invalidate_after_checked(&mut self, expr: &Value, owner: &str, symbols: &Symbols) {
        if contains_unproved_effect_with_vars(expr, owner, symbols, &self.facts) {
            self.invalidate_after(expr);
        }
    }

    fn forget_after_unverified(&mut self, owner: &str) {
        self.facts.clear();
        self.fresh_collections.clear();
        self.facts
            .insert("src".into(), Ty::Nullable(Box::new(Ty::Path(owner.into()))));
        self.facts.insert(STALE_REFERENCES.into(), Ty::Num);
        for name in self.slots.keys() {
            self.facts.insert(name.clone(), Ty::Unknown);
        }
        self.result_fact = Ty::Unknown;
    }
}

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct UnknownRootCount {
    pub category: String,
    pub symbol: String,
    pub path: String,
    pub line: usize,
    pub count: usize,
}

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct TypeCoverage {
    pub frontend_verified: bool,
    pub bridge_schema: u64,
    pub frontend_errors: Option<i64>,
    pub strict_declarations: usize,
    pub known_declarations: usize,
    pub unresolved_declarations: usize,
    pub checked_assignments: usize,
    pub unresolved_assignments: usize,
    pub unresolved_source_types: usize,
    pub unresolved_destination_types: usize,
    pub unresolved_both_types: usize,
    pub dynamic_operations: usize,
    pub typed_expressions: usize,
    pub unresolved_expressions: usize,
    pub resolved_calls: usize,
    pub unresolved_calls: usize,
    pub discharged_null_checks: usize,
    pub unverified_control_flow: usize,
    pub checked_procs_reused: usize,
    pub checked_procs_recomputed: usize,
    pub unresolved_by_kind: BTreeMap<String, usize>,
    pub unresolved_identifiers: BTreeMap<String, usize>,
    pub unresolved_causes: BTreeMap<String, usize>,
    #[serde(default)]
    pub unresolved_roots: BTreeMap<String, UnknownRootCount>,
}

impl TypeCoverage {
    fn add_delta(&mut self, delta: &Self) {
        macro_rules! add {
            ($($field:ident),+ $(,)?) => {
                $(self.$field += delta.$field;)+
            };
        }
        add!(
            strict_declarations,
            known_declarations,
            unresolved_declarations,
            checked_assignments,
            unresolved_assignments,
            unresolved_source_types,
            unresolved_destination_types,
            unresolved_both_types,
            dynamic_operations,
            typed_expressions,
            unresolved_expressions,
            resolved_calls,
            unresolved_calls,
            discharged_null_checks,
            unverified_control_flow,
        );
        for (key, value) in &delta.unresolved_by_kind {
            *self.unresolved_by_kind.entry(key.clone()).or_default() += value;
        }
        for (key, value) in &delta.unresolved_identifiers {
            *self.unresolved_identifiers.entry(key.clone()).or_default() += value;
        }
        for (key, value) in &delta.unresolved_causes {
            *self.unresolved_causes.entry(key.clone()).or_default() += value;
        }
        for (key, value) in &delta.unresolved_roots {
            self.unresolved_roots
                .entry(key.clone())
                .and_modify(|root| root.count += value.count)
                .or_insert_with(|| value.clone());
        }
    }
}

#[derive(serde::Serialize, serde::Deserialize)]
struct ProcShard {
    schema: u32,
    key: String,
    findings: Vec<StoredFinding>,
    coverage: TypeCoverage,
}

#[derive(serde::Serialize)]
struct BorrowedProcShard<'a> {
    schema: u32,
    key: &'a str,
    findings: Vec<StoredFinding>,
    coverage: &'a TypeCoverage,
}

#[derive(serde::Serialize, serde::Deserialize)]
struct StoredFinding {
    rule: String,
    path: String,
    line: usize,
    severity: String,
    message: String,
}

impl From<&Finding> for StoredFinding {
    fn from(finding: &Finding) -> Self {
        Self {
            rule: finding.rule.into(),
            path: finding.path.clone(),
            line: finding.line,
            severity: finding.severity.into(),
            message: finding.message.clone(),
        }
    }
}

fn known_rule(rule: &str) -> Option<&'static str> {
    macro_rules! rules {
        ($($rule:literal),+ $(,)?) => {
            match rule { $($rule => Some($rule),)+ _ => None }
        };
    }
    rules!(
        "broad-inferred-field-type",
        "conflicting-type-contract",
        "duplicate-argument",
        "duplicate-proc-definition",
        "field-override",
        "field-type-conflict",
        "local-type-conflict",
        "override-contract",
        "parameter-inference-limit",
        "read-before-assignment",
        "required-field-uninitialized",
        "return-inference-limit",
        "shadowed-type-guard",
        "strict-null-dereference",
        "strict-type-assignment",
        "unknown-argument-target",
        "unknown-field-type",
        "unknown-field-write",
        "unknown-override-result",
        "unknown-override-type",
        "unknown-parameter-type",
        "unknown-return-type",
        "unknown-type-flow",
        "unproven-initialization",
        "unresolved-append-target",
        "unresolved-argument-pack",
        "unresolved-argument-key",
        "unresolved-direct-call",
        "unresolved-dynamic-call",
        "unresolved-index-write",
        "unresolved-index",
        "unresolved-member-call",
        "unresolved-member-read",
        "unresolved-member-write",
        "unresolved-parent-call",
        "unresolved-parent-type",
        "unresolved-proc-version",
        "unresolved-type-enumeration",
        "unverified-ast-export",
        "unverified-control-flow",
        "unverified-inferred-parameter",
        "unverified-iterable",
        "unverified-iterator-element",
        "unverified-loop-fixed-point"
    )
}

fn load_proc_shard(directory: &Path, key: &str) -> Option<(Vec<Finding>, TypeCoverage)> {
    // Semantic keys include the analyzer binary, so older two-file entries
    // cannot match this binary's keys. Avoid a second failed filesystem lookup
    // for every cold procedure when populating a new cache generation.
    let envelope = fs::read(directory.join(format!("{key}.shard"))).ok()?;
    let payload_len = envelope.len().checked_sub(32)?;
    let (payload, checksum) = envelope.split_at(payload_len);
    if Sha256::digest(payload).as_slice() != checksum {
        return None;
    }
    let stored: ProcShard = serde_json::from_slice(payload).ok()?;
    if stored.schema != 1 || stored.key != key {
        return None;
    }
    let mut findings = Vec::with_capacity(stored.findings.len());
    for finding in stored.findings {
        findings.push(Finding {
            rule: known_rule(&finding.rule)?,
            path: finding.path,
            line: finding.line,
            severity: match finding.severity.as_str() {
                "error" => "error",
                "warning" => "warning",
                "info" => "info",
                _ => return None,
            },
            message: finding.message,
        });
    }
    Some((findings, stored.coverage))
}

fn store_proc_shard(
    directory: &Path,
    key: &str,
    findings: &[Finding],
    coverage: &TypeCoverage,
) -> io::Result<()> {
    // The caller has already attempted a read and created the directory.
    let stored = BorrowedProcShard {
        schema: 1,
        key,
        findings: findings.iter().map(StoredFinding::from).collect(),
        coverage,
    };
    let mut bytes = serde_json::to_vec(&stored)?;
    let checksum = Sha256::digest(&bytes);
    bytes.extend_from_slice(&checksum);
    let temporary = directory.join(format!("{key}.{}.tmp", std::process::id()));
    fs::write(&temporary, &bytes)?;
    let path = directory.join(format!("{key}.shard"));
    // Most stores populate a new semantic key. Avoid an extra metadata lookup
    // for every cold shard; only handle replacement after rename says it is
    // needed (notably on Windows).
    match fs::rename(&temporary, &path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
            fs::remove_file(&path)?;
            fs::rename(temporary, path)
        }
        Err(error) => Err(error),
    }
}

fn hash_value(hash: &mut Sha256, value: &[u8]) {
    hash.update((value.len() as u64).to_le_bytes());
    hash.update(value);
}

fn semantic_digest(checker: &Checker<'_>, mut hash: Sha256) -> io::Result<String> {
    hash_value(&mut hash, b"dm-health-proc-shards-v1");
    hash_value(&mut hash, &fs::read(std::env::current_exe()?)?);
    hash_value(&mut hash, format!("{:?}", checker.contracts).as_bytes());
    hash_value(&mut hash, &[u8::from(checker.selection.all)]);
    let mut modules = checker.selection.modules.clone();
    modules.sort();
    for module in modules {
        hash_value(&mut hash, module.as_bytes());
    }
    if let Some(files) = &checker.selection.files {
        let mut files: Vec<_> = files.iter().collect();
        files.sort();
        for file in files {
            hash_value(&mut hash, file.as_bytes());
        }
    }
    let mut fields: Vec<_> = checker.fields.iter().collect();
    fields.sort_by_key(|(key, _)| *key);
    for (key, field) in fields {
        hash_value(&mut hash, format!("{key:?}:{field:?}").as_bytes());
    }
    let mut procs: Vec<_> = checker.procs.iter().collect();
    procs.sort_by_key(|(key, _)| *key);
    for (key, proc) in procs {
        hash_value(&mut hash, format!("{key:?}:{proc:?}").as_bytes());
    }
    let mut versions: Vec<_> = checker.proc_versions.iter().collect();
    versions.sort_by_key(|(key, _)| *key);
    for (key, items) in versions {
        hash_value(&mut hash, format!("{key:?}:{items:?}").as_bytes());
    }
    let mut evidence: Vec<_> = checker.param_evidence.iter().collect();
    evidence.sort_by_key(|(key, _)| *key);
    for (key, item) in evidence {
        hash_value(&mut hash, format!("{key:?}:{item:?}").as_bytes());
    }
    Ok(format!("{:x}", hash.finalize()))
}

#[derive(Clone, Debug, Default)]
pub struct Selection {
    pub all: bool,
    pub modules: Vec<String>,
    pub files: Option<HashSet<String>>,
}

impl Selection {
    fn includes(&self, path: &str) -> bool {
        self.files.as_ref().is_none_or(|files| files.contains(path))
            && (self.all
                || self
                    .modules
                    .iter()
                    .any(|m| path.starts_with(&format!("{m}/"))))
    }
}

struct Checker<'a> {
    symbols: &'a Symbols,
    contracts: &'a [Contract],
    selection: &'a Selection,
    fields: HashMap<(String, String), FieldInfo>,
    overrides: Vec<Value>,
    procs: HashMap<(String, String), Signature>,
    proc_versions: HashMap<(String, String), Vec<Signature>>,
    checked_versions: HashMap<(String, String), usize>,
    param_evidence: HashMap<(String, String, usize), ParamEvidence>,
    return_bodies: HashMap<(String, String), Vec<(usize, Value)>>,
    new_bodies: HashMap<String, Value>,
    current_proc: Option<String>,
    current_proc_version: Option<usize>,
    inferred_locals: HashMap<String, Ty>,
    findings: Vec<Finding>,
    coverage: TypeCoverage,
}

impl Checker<'_> {
    fn literal_record_fact(
        &self,
        literal: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Option<Ty> {
        if kind(literal) != "DMASTList" || f(literal, "IsAList").as_bool() == Some(true) {
            return None;
        }
        let entries = f(literal, "Values").as_array()?;
        if entries.is_empty() || entries.len() > 64 {
            return None;
        }
        let mut fields = BTreeMap::new();
        for entry in entries {
            let key = f(entry, "Key");
            if kind(key) != "DMASTConstantString" {
                return None;
            }
            let name = f(key, "Value").as_str()?;
            let value = f(entry, "Value");
            if contains_unknown_effect(value) {
                return None;
            }
            let ty = self.expression(value, vars, owner);
            if !ty.is_precise() || fields.insert(name.into(), (ty, false)).is_some() {
                return None;
            }
        }
        Some(Ty::Record(fields))
    }

    fn scan_local_type_flow(
        &self,
        block: &Value,
        owner: &str,
        flow: &mut LocalTypeFlow,
        evidence: &mut HashMap<usize, Ty>,
    ) {
        let Some(statements) = simple_statements(block) else {
            return;
        };
        for statement in statements {
            match kind(statement) {
                "DMASTProcStatementVarDeclaration" => {
                    let Some(name) = f(statement, "Name").as_str() else {
                        continue;
                    };
                    let initializer = f(statement, "Value");
                    let native = declared(f(statement, "Type"), f(statement, "ValueType"));
                    let actual = if contains_mutation(initializer) {
                        Ty::Unknown
                    } else if initializer.is_null() {
                        Ty::Null
                    } else {
                        self.expression(initializer, &flow.facts, owner)
                    };
                    invalidate_after(initializer, &mut flow.facts);
                    if contains_mutation(initializer) {
                        for fact in flow.facts.values_mut() {
                            *fact = Ty::Unknown;
                        }
                    }
                    overwrite_place_fact(
                        &mut flow.facts,
                        name,
                        if actual == Ty::Null && native.is_precise() {
                            Ty::Null
                        } else {
                            actual
                        },
                    );
                    if !initializer.is_null() || f(statement, "IsGlobal").as_bool() == Some(true) {
                        flow.assigned.insert(name.into());
                    }
                }
                "DMASTProcStatementExpression" => {
                    let expr = f(statement, "Expression");
                    if kind(expr) == "DMASTAssign" {
                        let rhs = f(expr, "RHS");
                        let actual = if contains_mutation(rhs) {
                            Ty::Unknown
                        } else {
                            self.expression(rhs, &flow.facts, owner)
                        };
                        if kind(f(expr, "LHS")) == "DMASTIdentifier" {
                            if let Some(name) = f(f(expr, "LHS"), "Identifier").as_str() {
                                evidence.insert(rhs as *const Value as usize, actual.clone());
                                invalidate_after(rhs, &mut flow.facts);
                                if contains_mutation(rhs) {
                                    for fact in flow.facts.values_mut() {
                                        *fact = Ty::Unknown;
                                    }
                                }
                                overwrite_place_fact(&mut flow.facts, name, actual);
                                flow.assigned.insert(name.into());
                            }
                        } else {
                            invalidate_after(expr, &mut flow.facts);
                            for fact in flow.facts.values_mut() {
                                *fact = Ty::Unknown;
                            }
                        }
                    } else {
                        invalidate_after(expr, &mut flow.facts);
                        if contains_mutation(expr) {
                            for fact in flow.facts.values_mut() {
                                *fact = Ty::Unknown;
                            }
                        }
                    }
                }
                "DMASTProcStatementIf" => {
                    let condition = f(statement, "Condition");
                    invalidate_after(condition, &mut flow.facts);
                    if contains_mutation(condition) {
                        for fact in flow.facts.values_mut() {
                            *fact = Ty::Unknown;
                        }
                    }
                    let mut yes = flow.clone();
                    let mut no = flow.clone();
                    if !contains_unknown_effect(condition) {
                        narrow(condition, true, &mut yes.facts);
                        narrow(condition, false, &mut no.facts);
                    }
                    self.scan_local_type_flow(f(statement, "Body"), owner, &mut yes, evidence);
                    self.scan_local_type_flow(f(statement, "ElseBody"), owner, &mut no, evidence);
                    let yes_returns = simple_block_returns(f(statement, "Body"));
                    let no_returns = simple_block_returns(f(statement, "ElseBody"));
                    if yes_returns && no_returns {
                        return;
                    }
                    if yes_returns && !no_returns {
                        *flow = no;
                    } else if no_returns && !yes_returns {
                        *flow = yes;
                    } else {
                        flow.facts = join_env(&yes.facts, &no.facts, self.symbols);
                        flow.assigned = yes.assigned.intersection(&no.assigned).cloned().collect();
                    }
                }
                "DMASTProcStatementReturn" => break,
                _ => {
                    // Loops, switches, and deferred blocks need a fixed point or
                    // path-specific state. Their writes remain in the all-write
                    // inventory but get no identifier-derived proof here. They
                    // may change an earlier local before a later assignment.
                    for fact in flow.facts.values_mut() {
                        *fact = Ty::Unknown;
                    }
                }
            }
        }
    }

    fn infer_local_storage(
        &self,
        body: &Value,
        owner: &str,
        sig: &Signature,
    ) -> HashMap<String, Ty> {
        let mut collected = LocalWrites::default();
        collect_local_writes(body, &mut collected);
        for param in &sig.parameters {
            collected.repeated.insert(param.name.clone());
        }
        let mut flow = LocalTypeFlow::default();
        flow.facts.insert("src".into(), Ty::Path(owner.into()));
        for param in &sig.parameters {
            flow.facts
                .insert(param.name.clone(), with_nullable(param.ty.clone(), true));
            flow.assigned.insert(param.name.clone());
        }
        for declaration in &collected.declarations {
            if let Some(name) = f(declaration, "Name").as_str() {
                flow.facts.entry(name.into()).or_insert(Ty::Unknown);
            }
        }
        let mut ordered_evidence = HashMap::new();
        self.scan_local_type_flow(body, owner, &mut flow, &mut ordered_evidence);
        let mut inferred = HashMap::new();
        for declaration in &collected.declarations {
            let Some(name) = f(declaration, "Name").as_str() else {
                continue;
            };
            if collected.repeated.contains(name) || collected.unsafe_writes.contains(name) {
                continue;
            }
            let declaration_site = source(declaration);
            if collected.write_sites.get(name).is_some_and(|sites| {
                sites.iter().any(|site| {
                    site.0 == "<unknown>"
                        || site.0 != declaration_site.0
                        || site.1 <= declaration_site.1
                })
            }) {
                continue;
            }
            let native = declared(f(declaration, "Type"), f(declaration, "ValueType"));
            if native != Ty::Unknown || f(declaration, "IsGlobal").as_bool() == Some(true) {
                continue;
            }
            let initializer = f(declaration, "Value");
            if !initializer.is_null() && kind(initializer) != "DMASTConstantNull" {
                continue;
            }
            let Some(writes) = collected
                .writes
                .get(name)
                .filter(|writes| !writes.is_empty())
            else {
                continue;
            };
            let mut candidate: Option<Ty> = None;
            for rhs in writes {
                // An identifier may denote a variable that is still null
                // at this write, regardless of its declared storage type.
                // Source-order flow is checked later; this prepass only
                // accepts self-contained, effect-free value expressions.
                let ty =
                    if let Some(proved) = ordered_evidence.get(&(*rhs as *const Value as usize)) {
                        proved.clone()
                    } else if !contains_identifier(rhs)
                        && (!contains_unknown_effect(rhs)
                            || matches!(kind(rhs), "DMASTNewPath" | "DMASTNewModifiedType"))
                    {
                        self.expression(rhs, &HashMap::new(), owner)
                    } else {
                        Ty::Unknown
                    };
                if !ty.is_precise() || ty.may_be_null() {
                    candidate = None;
                    break;
                }
                candidate = Some(match candidate {
                    Some(previous) => previous.join(&ty, self.symbols),
                    None => ty,
                });
                if !candidate
                    .as_ref()
                    .is_some_and(|ty| ty.is_precise() && !matches!(ty, Ty::OneOf(_)))
                {
                    candidate = None;
                    break;
                }
            }
            if let Some(ty) = candidate {
                inferred.insert(name.into(), ty);
            }
        }
        inferred
    }

    fn strict(&self, node: &Value) -> bool {
        self.selection.includes(source(node).0.as_str())
    }

    fn field_key(&self, owner: &str, name: &str) -> Option<(String, String)> {
        let mut current = owner.to_owned();
        let mut seen = HashSet::new();
        loop {
            if !seen.insert(current.clone()) {
                return None;
            }
            let key = (current.clone(), name.into());
            if self.fields.contains_key(&key) {
                return Some(key);
            }
            current = self.symbols.parent(&current)?;
        }
    }

    fn inherited_builtin_field_type(&self, owner: &str, name: &str) -> Option<Ty> {
        let mut current = Some(owner.to_owned());
        let mut seen = HashSet::new();
        while let Some(path) = current {
            if !seen.insert(path.clone()) {
                return None;
            }
            if let Some(field) = builtin_field_type(&path, name) {
                return Some(field);
            }
            current = self.symbols.parent(&path);
        }
        None
    }

    fn reflected_field_key(
        &self,
        expr: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Option<(String, String)> {
        if kind(expr) != "DMASTDereference" {
            return None;
        }
        let base = f(expr, "Expression");
        let operations = f(expr, "Operations").as_array()?;
        let (receiver, index) = if kind(base) == "DMASTIdentifier"
            && f(base, "Identifier").as_str() == Some("vars")
            && !vars.contains_key("vars")
            && operations.len() == 1
        {
            (owner.to_owned(), &operations[0])
        } else if operations.len() == 2
            && kind(&operations[0]) == "FieldOperation"
            && f(&operations[0], "Identifier").as_str() == Some("vars")
        {
            let Ty::Path(receiver) = self.expression(base, vars, owner).nonnull() else {
                return None;
            };
            (receiver, &operations[1])
        } else {
            return None;
        };
        if kind(index) != "IndexOperation" {
            return None;
        }
        let key = f(index, "Index");
        if kind(key) != "DMASTConstantString" {
            return None;
        }
        self.field_key(&receiver, f(key, "Value").as_str()?)
    }

    fn indexed_field_key(
        &self,
        expr: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
        locals: &HashSet<String>,
    ) -> Option<((String, String), Ty)> {
        if kind(expr) != "DMASTDereference" {
            return None;
        }
        let [index] = f(expr, "Operations").as_array()?.as_slice() else {
            return None;
        };
        if kind(index) != "IndexOperation" {
            return None;
        }
        let base = f(expr, "Expression");
        let key = if kind(base) == "DMASTIdentifier" {
            let name = f(base, "Identifier").as_str()?;
            if locals.contains(name) {
                return None;
            }
            self.field_key(owner, name)?
        } else if kind(base) == "DMASTDereference" {
            let [field] = f(base, "Operations").as_array()?.as_slice() else {
                return None;
            };
            if kind(field) != "FieldOperation" {
                return None;
            }
            let Ty::Path(receiver) = self
                .expression(f(base, "Expression"), vars, owner)
                .nonnull()
            else {
                return None;
            };
            self.field_key(&receiver, f(field, "Identifier").as_str()?)?
        } else {
            return None;
        };
        Some((key, self.expression(f(index, "Index"), vars, owner)))
    }

    fn expression(&self, expr: &Value, vars: &HashMap<String, Ty>, owner: &str) -> Ty {
        if let Some(key) = self.reflected_field_key(expr, vars, owner) {
            let ty = self.fields[&key].ty.clone();
            let mut ty = if vars.contains_key(STALE_REFERENCES) {
                stale_field_after_unknown_effect(&ty)
            } else {
                ty
            };
            if f(expr, "Operations")
                .as_array()
                .is_some_and(|ops| ops.iter().any(|op| f(op, "Safe").as_bool() == Some(true)))
                && !ty.may_be_null()
            {
                ty = Ty::Nullable(Box::new(ty));
            }
            return ty;
        }
        if kind(expr) == "DMASTDereference" {
            if let Some(fact) = place(expr).and_then(|key| vars.get(&key)) {
                return fact.clone();
            }
        }
        match kind(expr) {
            "DMASTExpressionWrapped" => self.expression(f(expr, "Value"), vars, owner),
            "DMASTConstantNull" => Ty::Null,
            "DMASTConstantInteger" | "DMASTConstantFloat" => Ty::Num,
            // These OpenDream builtin nodes have a fixed result shape. Their
            // arguments are inspected separately, so an unknown argument
            // need not erase the known result type.
            "DMASTLength"
            | "DMASTProb"
            | "DMASTGetDir"
            | "DMASTAbs"
            | "DMASTLog"
            | "DMASTSqrt"
            | "DMASTSin"
            | "DMASTCos"
            | "DMASTArctan"
            | "DMASTArctan2"
            | "DMASTExpressionInRange" => Ty::Num,
            "DMASTGetStep" => Ty::Nullable(Box::new(Ty::Path("/turf".into()))),
            "DMASTConstantString"
            | "DMASTStringFormat"
            | "DMASTNameof"
            | "DMASTRgb"
            | "DMASTAddText" => Ty::Text,
            "DMASTConstantResource" => f(expr, "Path")
                .as_str()
                .map(resource_type)
                .unwrap_or(Ty::Unknown),
            "DMASTVarDeclExpression" => iterator_declaration(expr)
                .map(|(_, ty)| ty)
                .unwrap_or(Ty::Unknown),
            "DMASTConstantPath" => f(f(expr, "Value"), "Path")
                .as_str()
                .map(|p| Ty::TypePath(p.into()))
                .unwrap_or(Ty::Unknown),
            "DMASTUpwardPathSearch" => {
                let base = f(f(f(expr, "Path"), "Value"), "Path").as_str();
                let search = f(f(expr, "Search"), "Path").as_str();
                let (Some(base), Some(name)) =
                    (base, search.and_then(|search| search.strip_prefix("proc/")))
                else {
                    return Ty::Unknown;
                };
                if name.is_empty() || name.contains('/') {
                    return Ty::Unknown;
                }
                let mut current = base.to_owned();
                let mut visited = HashSet::new();
                while visited.insert(current.clone()) {
                    if self.procs.contains_key(&(current.clone(), name.into())) {
                        return Ty::TypePath(if current == "/" {
                            format!("/proc/{name}")
                        } else {
                            format!("{current}/proc/{name}")
                        });
                    }
                    if current == "/" {
                        break;
                    }
                    current = self.symbols.parent(&current).unwrap_or_else(|| "/".into());
                }
                Ty::Unknown
            }
            "DMASTList" | "DMASTNewList" => {
                let is_alist = f(expr, "IsAList").as_bool() == Some(true);
                let elements = if kind(expr) == "DMASTList" {
                    f(expr, "Values")
                } else {
                    f(expr, "Parameters")
                };
                if elements.as_array().is_some_and(Vec::is_empty) {
                    return if is_alist {
                        Ty::EmptyAlist
                    } else {
                        Ty::EmptyList
                    };
                }
                let mut element: Option<Ty> = None;
                let mut key_type: Option<Ty> = None;
                let mut saw_positional = false;
                let mut saw_keyed = false;
                for arg in elements.as_array().into_iter().flatten() {
                    let key = f(arg, "Key");
                    if key.is_null() {
                        saw_positional = true;
                    } else {
                        saw_keyed = true;
                        let current_key = self.expression(key, vars, owner);
                        key_type = Some(match key_type {
                            Some(previous) => previous.join(&current_key, self.symbols),
                            None => current_key,
                        });
                    }
                    let current = self.expression(f(arg, "Value"), vars, owner);
                    element = Some(match element {
                        Some(previous) => previous.join(&current, self.symbols),
                        None => current,
                    });
                }
                if is_alist && saw_positional {
                    Ty::Unknown
                } else if saw_keyed && saw_positional {
                    Ty::List(Box::new(element.unwrap_or(Ty::Unknown)))
                } else if saw_keyed {
                    let key = Box::new(key_type.unwrap_or(Ty::Unknown));
                    let value = Box::new(element.unwrap_or(Ty::Unknown));
                    if is_alist {
                        Ty::Alist(key, value)
                    } else {
                        Ty::Assoc(key, value)
                    }
                } else {
                    Ty::List(Box::new(element.unwrap_or(Ty::Unknown)))
                }
            }
            "DMASTDimensionalList" => f(expr, "Sizes")
                .as_array()
                .map(|sizes| dimensional_list_type(sizes.len()))
                .unwrap_or(Ty::Unknown),
            "DMASTNewPath" => {
                let path = f(f(f(expr, "Path"), "Value"), "Path").as_str();
                let dimensions = f(expr, "Parameters").as_array().map(Vec::len);
                let empty = dimensions == Some(0);
                match (path, empty) {
                    (Some("/list"), _) => {
                        dimensions.map(dimensional_list_type).unwrap_or(Ty::Unknown)
                    }
                    (Some("/alist"), true) => Ty::EmptyAlist,
                    (Some("/alist"), false) => {
                        Ty::Alist(Box::new(Ty::Unknown), Box::new(Ty::Unknown))
                    }
                    (Some(path), _) => Ty::Path(path.into()),
                    _ => Ty::Unknown,
                }
            }
            "DMASTNewModifiedType" => f(f(f(expr, "Type"), "Value"), "Path")
                .as_str()
                .map(|p| Ty::Path(p.into()))
                .unwrap_or(Ty::Unknown),
            "DMASTNewExpr" => match self.expression(f(expr, "Expression"), vars, owner) {
                Ty::TypePath(path) if path == "/list" => f(expr, "Parameters")
                    .as_array()
                    .map(|params| dimensional_list_type(params.len()))
                    .unwrap_or(Ty::Unknown),
                Ty::TypePath(path) if path == "/alist" => {
                    if f(expr, "Parameters").as_array().is_some_and(Vec::is_empty) {
                        Ty::EmptyAlist
                    } else {
                        Ty::Alist(Box::new(Ty::Unknown), Box::new(Ty::Unknown))
                    }
                }
                Ty::TypePath(path) if constructible_datum_bound(&path, self.symbols) => {
                    Ty::Path(path)
                }
                _ => Ty::Unknown,
            },
            "DMASTPick" => {
                let mut choices = f(expr, "Values").as_array().into_iter().flatten();
                let Some(first) = choices.next() else {
                    return Ty::Unknown;
                };
                let mut selected = self.expression(f(first, "Value"), vars, owner);
                for choice in choices {
                    selected = selected.join(
                        &self.expression(f(choice, "Value"), vars, owner),
                        self.symbols,
                    );
                }
                selected
            }
            "DMASTLocate" => {
                let target = f(expr, "Expression");
                if target.is_null() {
                    return Ty::Unknown;
                }
                let result = self.expression(target, vars, owner);
                match result {
                    Ty::TypePath(path) if constructible_datum_bound(&path, self.symbols) => {
                        Ty::Nullable(Box::new(Ty::Path(path)))
                    }
                    _ => Ty::Unknown,
                }
            }
            "DMASTLocateCoordinates" => Ty::Nullable(Box::new(Ty::Path("/turf".into()))),
            "DMASTInput" => {
                let mode = f(expr, "Types").as_str();
                let typed = mode
                    .map(|raw| declared_type(None, Some(&raw.to_ascii_lowercase())))
                    .map(|raw| Ty::parse(&raw))
                    .unwrap_or(Ty::Unknown);
                let choices = f(expr, "List");
                let selected = if choices.is_null() {
                    typed
                } else {
                    match self.expression(choices, vars, owner).nonnull() {
                        Ty::List(element) => *element,
                        Ty::Assoc(key, _) | Ty::Alist(key, _) => *key,
                        _ => typed,
                    }
                };
                // The user can cancel a dialog even when its choices are typed.
                if selected.is_precise() && !selected.may_be_null() {
                    Ty::Nullable(Box::new(selected))
                } else {
                    selected
                }
            }
            "DMASTInitial" => {
                let target = f(expr, "Value");
                let key = match kind(target) {
                    "DMASTIdentifier" => {
                        let name = f(target, "Identifier").as_str().unwrap_or("");
                        if vars.contains_key(name) {
                            None
                        } else {
                            self.field_key(owner, name)
                        }
                    }
                    "DMASTDereference" => {
                        let operations = f(target, "Operations").as_array();
                        if let Some([operation]) = operations.map(Vec::as_slice) {
                            if kind(operation) == "FieldOperation" {
                                let receiver =
                                    self.expression(f(target, "Expression"), vars, owner);
                                if let Ty::Path(path) = receiver.nonnull() {
                                    self.field_key(
                                        &path,
                                        f(operation, "Identifier").as_str().unwrap_or(""),
                                    )
                                } else {
                                    None
                                }
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    }
                    _ => None,
                };
                key.and_then(|key| self.fields.get(&key))
                    .map(|field| {
                        if field.initially_null {
                            Ty::Null
                        } else {
                            field.ty.clone()
                        }
                    })
                    .unwrap_or(Ty::Unknown)
            }
            "DMASTIdentifier" => {
                let name = f(expr, "Identifier").as_str().unwrap_or("");
                if name == "src" {
                    vars.get("src")
                        .cloned()
                        .unwrap_or_else(|| Ty::Path(owner.into()))
                } else if name == "GLOB" {
                    Ty::Path("/datum/controller/global_vars".into())
                } else if name == "global" {
                    // BYOND's `global.name` namespace addresses root global
                    // variables, which OpenDream exports as owner "/".
                    Ty::Path("/".into())
                } else if name == "args" {
                    // Built-in current-proc argument list. Its elements depend
                    // on the actual call and cannot be assigned one static type.
                    Ty::List(Box::new(Ty::Unknown))
                } else if name == "world" {
                    Ty::Path("/world".into())
                } else if name == "usr" {
                    Ty::Nullable(Box::new(Ty::Path("/mob".into())))
                } else {
                    vars.get(name).cloned().unwrap_or_else(|| {
                        self.field_key(owner, name)
                            .and_then(|key| self.fields.get(&key))
                            .map(|field| {
                                let ty = field.ty.clone();
                                if vars.contains_key(STALE_REFERENCES) {
                                    stale_field_after_unknown_effect(&ty)
                                } else {
                                    ty
                                }
                            })
                            .unwrap_or(Ty::Unknown)
                    })
                }
            }
            "DMASTProcCall" => {
                let callable = f(expr, "Callable");
                if kind(callable) == "DMASTCallableSuper" {
                    return self
                        .current_proc
                        .as_ref()
                        .and_then(|name| self.parent_signature(owner, name))
                        .map(|sig| sig.result.clone())
                        .unwrap_or(Ty::Unknown);
                }
                let name = f(callable, "Identifier").as_str().unwrap_or("");
                if matches!(name, "islist" | "isnum" | "istext") {
                    return if checked_unary_builtin(expr) {
                        Ty::Num
                    } else {
                        Ty::Unknown
                    };
                }
                if name == "ispath" {
                    return if checked_ispath_builtin(expr) {
                        Ty::Num
                    } else {
                        Ty::Unknown
                    };
                }
                if matches!(name, "typesof" | "subtypesof") {
                    return self.type_enumeration_result(expr, vars, owner);
                }
                if let Some(result) =
                    self.preference_read_result(owner, name, f(expr, "Parameters"), vars, owner)
                {
                    return result;
                }
                if let Some(result) =
                    self.tgui_input_list_result(owner, name, f(expr, "Parameters"), vars)
                {
                    return result;
                }
                if let Some(result) =
                    self.tgui_alert_result(owner, name, f(expr, "Parameters"), vars)
                {
                    return result;
                }
                if let Some(result) =
                    self.list2text_result(owner, name, f(expr, "Parameters"), vars)
                {
                    return result;
                }
                if let Some(result) =
                    self.shape_preserving_list_result(owner, name, f(expr, "Parameters"), vars)
                {
                    return result;
                }
                if let Some(result) =
                    self.generic_collection_result(owner, name, f(expr, "Parameters"), vars)
                {
                    return result;
                }
                let signature = self.signature(owner, name);
                if signature.is_none_or(standard_builtin_signature) {
                    if let Some(result) = self.builtin_result(expr, name, vars, owner) {
                        return result;
                    }
                }
                if let Some(signature) = signature {
                    return signature.result.clone();
                }
                Ty::Unknown
            }
            "DMASTCall" => self
                .dynamic_signature(expr, vars, owner)
                .map(|sig| sig.result)
                .unwrap_or(Ty::Unknown),
            "DMASTDereference" => {
                let mut ty = self.expression(f(expr, "Expression"), vars, owner);
                let mut place_key = place(f(expr, "Expression"));
                for op in f(expr, "Operations").as_array().into_iter().flatten() {
                    let member = f(op, "Identifier").as_str().unwrap_or("");
                    let safe = f(op, "Safe").as_bool().unwrap_or(false);
                    if kind(op) == "IndexOperation" {
                        place_key = place_key
                            .as_deref()
                            .and_then(|prefix| indexed_place_key(prefix, f(op, "Index")));
                        ty = match ty.nonnull() {
                            Ty::List(value) => Ty::Nullable(value),
                            Ty::Assoc(_, value) | Ty::Alist(_, value) => Ty::Nullable(value),
                            Ty::Record(fields) => {
                                let index = f(op, "Index");
                                if kind(index) == "DMASTConstantString" {
                                    f(index, "Value")
                                        .as_str()
                                        .and_then(|name| fields.get(name))
                                        .map(|(value, _)| Ty::Nullable(Box::new(value.clone())))
                                        .unwrap_or(Ty::Unknown)
                                } else {
                                    Ty::Unknown
                                }
                            }
                            _ => Ty::Unknown,
                        };
                        if safe && !ty.may_be_null() {
                            ty = Ty::Nullable(Box::new(ty));
                        }
                        if let Some(fact) = place_key.as_ref().and_then(|key| vars.get(key)) {
                            ty = fact.clone();
                        }
                        continue;
                    }
                    if kind(op) == "FieldOperation" {
                        if let Some(builtin) = collection_field_type(&ty.nonnull(), member) {
                            place_key = None;
                            ty = if safe {
                                Ty::Nullable(Box::new(builtin))
                            } else {
                                builtin
                            };
                            continue;
                        }
                    }
                    let Ty::Path(ref receiver) = ty.nonnull() else {
                        return Ty::Unknown;
                    };
                    ty = if kind(op) == "FieldOperation" {
                        self.field_key(receiver, member)
                            .and_then(|key| self.fields.get(&key))
                            .map(|field| {
                                let declared = field.ty.clone();
                                if vars.contains_key(STALE_REFERENCES) {
                                    stale_field_after_unknown_effect(&declared)
                                } else {
                                    declared
                                }
                            })
                            .unwrap_or_else(|| {
                                self.inherited_builtin_field_type(receiver, member)
                                    .unwrap_or(Ty::Unknown)
                            })
                    } else if kind(op) == "CallOperation" {
                        self.preference_read_result(
                            receiver,
                            member,
                            f(op, "Parameters"),
                            vars,
                            owner,
                        )
                        .or_else(|| {
                            self.weakref_resolve_result(receiver, member, f(op, "Parameters"))
                        })
                        .or_else(|| self.signature(receiver, member).map(|s| s.result.clone()))
                        .unwrap_or(Ty::Unknown)
                    } else {
                        Ty::Unknown
                    };
                    if kind(op) == "FieldOperation" {
                        if let Some(key) = place_key.as_mut() {
                            key.push('.');
                            key.push_str(member);
                            if let Some(fact) = vars.get(key) {
                                ty = fact.clone();
                            }
                        }
                    } else {
                        place_key = None;
                    }
                    if safe && !ty.may_be_null() {
                        ty = Ty::Nullable(Box::new(ty));
                    }
                }
                ty
            }
            "DMASTTernary" => {
                let condition = f(expr, "A");
                if let Some(truth) = literal_truthiness(condition) {
                    return self.expression(f(expr, if truth { "B" } else { "C" }), vars, owner);
                }
                let mut base = vars.clone();
                invalidate_after(condition, &mut base);
                let mut yes = base.clone();
                let mut no = base;
                if !contains_unknown_effect(condition) {
                    seed_guard_facts(condition, &mut yes, self, owner);
                    seed_guard_facts(condition, &mut no, self, owner);
                    narrow(condition, true, &mut yes);
                    narrow(condition, false, &mut no);
                }
                self.expression(f(expr, "B"), &yes, owner)
                    .join(&self.expression(f(expr, "C"), &no, owner), self.symbols)
            }
            // DM assignments are expressions whose value is the assigned
            // right-hand side, including when used directly in `return`.
            "DMASTAssign" => self.expression(f(expr, "RHS"), vars, owner),
            "DMASTAdd" => {
                let left_expr = f(expr, "LHS");
                let right_expr = f(expr, "RHS");
                let left = self.expression(left_expr, vars, owner);
                let right = self.expression(right_expr, vars, owner);
                match (&left, &right) {
                    (a, b) if numeric_operand(a) && numeric_operand(b) => Ty::Num,
                    (Ty::Text, Ty::Text) => Ty::Text,
                    (Ty::EmptyList, Ty::EmptyList) => Ty::EmptyList,
                    (Ty::EmptyList, Ty::List(_)) => right,
                    (Ty::List(_), Ty::EmptyList) => left,
                    (Ty::EmptyList, _)
                        if right.is_precise() && !matches!(right, Ty::Assoc(_, _)) =>
                    {
                        Ty::List(Box::new(right))
                    }
                    (Ty::List(a), Ty::List(b)) if a == b => left,
                    (Ty::List(a), Ty::List(b)) => Ty::List(Box::new(a.join(b, self.symbols))),
                    (Ty::List(a), _)
                        if !matches!(right, Ty::List(_) | Ty::Assoc(_, _))
                            && a.as_ref() == &right
                            && right.is_precise() =>
                    {
                        left
                    }
                    (Ty::List(_), _)
                        if empty_list_literal(left_expr)
                            && !matches!(right, Ty::List(_) | Ty::Assoc(_, _))
                            && right.is_precise() =>
                    {
                        Ty::List(Box::new(right))
                    }
                    _ => Ty::Unknown,
                }
            }
            "DMASTAppend" => {
                let left = self.expression(f(expr, "LHS"), vars, owner);
                let right = self.expression(f(expr, "RHS"), vars, owner);
                match (&left, &right) {
                    (a, b) if numeric_operand(a) && numeric_operand(b) => Ty::Num,
                    (Ty::Text, Ty::Text) => Ty::Text,
                    (Ty::EmptyList, Ty::EmptyList) => Ty::EmptyList,
                    (Ty::EmptyList, Ty::List(_)) => right,
                    (Ty::EmptyList, value)
                        if value.is_precise()
                            && !matches!(
                                value,
                                Ty::Assoc(_, _) | Ty::Alist(_, _) | Ty::EmptyAlist
                            ) =>
                    {
                        Ty::List(Box::new(value.clone()))
                    }
                    (Ty::List(_), Ty::EmptyList) => left,
                    (Ty::List(a), Ty::List(b)) if a == b && a.is_precise() => left,
                    (Ty::List(a), Ty::List(b)) => Ty::List(Box::new(a.join(b, self.symbols))),
                    (Ty::List(a), _)
                        if !matches!(right, Ty::List(_) | Ty::Assoc(_, _))
                            && a.as_ref() == &right
                            && right.is_precise() =>
                    {
                        left
                    }
                    (Ty::List(a), Ty::Assoc(_, _) | Ty::Alist(_, _)) => {
                        Ty::List(Box::new(a.join(&Ty::Unknown, self.symbols)))
                    }
                    (Ty::List(a), value) => Ty::List(Box::new(a.join(value, self.symbols))),
                    _ => Ty::Unknown,
                }
            }
            "DMASTSubtract" => {
                let left = self.expression(f(expr, "LHS"), vars, owner);
                let right = self.expression(f(expr, "RHS"), vars, owner);
                match left {
                    Ty::EmptyList | Ty::List(_) => left,
                    Ty::Num | Ty::Null
                        if matches!(right, Ty::Num | Ty::Null)
                            || matches!(&right, Ty::Nullable(inner) if **inner == Ty::Num) =>
                    {
                        Ty::Num
                    }
                    Ty::Nullable(inner)
                        if *inner == Ty::Num
                            && (matches!(right, Ty::Num | Ty::Null)
                                || matches!(right, Ty::Nullable(ref inner) if **inner == Ty::Num)) =>
                    {
                        Ty::Num
                    }
                    _ => Ty::Unknown,
                }
            }
            "DMASTRemove" => {
                let left = self.expression(f(expr, "LHS"), vars, owner);
                let right = self.expression(f(expr, "RHS"), vars, owner);
                match (&left, &right) {
                    (Ty::EmptyList | Ty::List(_), _) => left,
                    (a, b) if numeric_operand(a) && numeric_operand(b) => Ty::Num,
                    _ => Ty::Unknown,
                }
            }
            "DMASTMask" => {
                let left = self.expression(f(expr, "LHS"), vars, owner);
                let right = self.expression(f(expr, "RHS"), vars, owner);
                match (&left, &right) {
                    (a, b) if numeric_operand(a) && numeric_operand(b) => Ty::Num,
                    (Ty::Num, b) if b.has_unknown() => Ty::Num,
                    // List intersection can only retain elements from its
                    // left operand; the right operand cannot add a new type.
                    (Ty::List(_), _) => left,
                    (Ty::EmptyList, _) => Ty::EmptyList,
                    _ => Ty::Unknown,
                }
            }
            "DMASTCombine" => {
                let left = self.expression(f(expr, "LHS"), vars, owner);
                let right = self.expression(f(expr, "RHS"), vars, owner);
                match (&left, &right) {
                    (a, b) if numeric_operand(a) && numeric_operand(b) => Ty::Num,
                    // With a proved numeric left operand, |= is numeric on
                    // every successful execution. The unknown right operand
                    // still needs its own compatibility check.
                    (Ty::Num, b) if b.has_unknown() => Ty::Num,
                    (Ty::EmptyList, Ty::EmptyList) => Ty::EmptyList,
                    (Ty::EmptyList, Ty::List(_)) => right,
                    (Ty::EmptyList, value)
                        if value.is_precise()
                            && !matches!(
                                value,
                                Ty::Assoc(_, _) | Ty::Alist(_, _) | Ty::EmptyAlist
                            ) =>
                    {
                        Ty::List(Box::new(value.clone()))
                    }
                    (Ty::List(_), Ty::EmptyList) => left,
                    (Ty::List(a), Ty::List(b)) => Ty::List(Box::new(a.join(b, self.symbols))),
                    (Ty::List(a), value) => Ty::List(Box::new(a.join(value, self.symbols))),
                    _ => Ty::Unknown,
                }
            }
            "DMASTMultiply" | "DMASTDivide" | "DMASTModulus" | "DMASTPower" | "DMASTLeftShift"
            | "DMASTRightShift" | "DMASTBinaryAnd" | "DMASTBinaryOr" | "DMASTBinaryXor" => {
                let a = self.expression(f(expr, "LHS"), vars, owner);
                let b = self.expression(f(expr, "RHS"), vars, owner);
                if numeric_operand(&a) && numeric_operand(&b) {
                    Ty::Num
                } else if kind(expr) == "DMASTBinaryAnd" && matches!(a, Ty::List(_) | Ty::EmptyList)
                {
                    a
                } else if matches!(
                    kind(expr),
                    "DMASTBinaryOr" | "DMASTBinaryAnd" | "DMASTBinaryXor"
                ) && a == Ty::Num
                    && b.has_unknown()
                {
                    // List and icon variants of these bitwise operators need
                    // a list or icon on the left. With a proved numeric left
                    // operand, a successful result is numeric, even though
                    // the unknown right operand still needs checking.
                    Ty::Num
                } else {
                    Ty::Unknown
                }
            }
            "DMASTBinaryNot" => {
                if numeric_operand(&self.expression(f(expr, "Value"), vars, owner)) {
                    Ty::Num
                } else {
                    Ty::Unknown
                }
            }
            "DMASTNegate" | "DMASTPreIncrement" | "DMASTPostIncrement" | "DMASTPreDecrement"
            | "DMASTPostDecrement" => {
                if numeric_operand(&self.expression(f(expr, "Value"), vars, owner)) {
                    Ty::Num
                } else {
                    Ty::Unknown
                }
            }
            "DMASTEqual"
            | "DMASTNotEqual"
            | "DMASTGreaterThan"
            | "DMASTGreaterThanOrEqual"
            | "DMASTLessThan"
            | "DMASTLessThanOrEqual"
            | "DMASTNot"
            | "DMASTIsNull"
            | "DMASTIsType"
            | "DMASTImplicitIsType"
            | "DMASTIsSaved" => Ty::Num,
            "DMASTAnd" | "DMASTOr" => {
                let lhs_expr = f(expr, "LHS");
                if let Some(truth) = literal_truthiness(lhs_expr) {
                    let evaluate_rhs = truth == (kind(expr) == "DMASTAnd");
                    return self.expression(
                        if evaluate_rhs {
                            f(expr, "RHS")
                        } else {
                            lhs_expr
                        },
                        vars,
                        owner,
                    );
                }
                let lhs = self.expression(lhs_expr, vars, owner);
                // Logical operators return the last operand evaluated. A
                // non-null reference is always truthy; a nullable reference
                // can short-circuit only with null.
                if !contains_unknown_effect(lhs_expr) {
                    if always_truthy_type(&lhs) {
                        return if kind(expr) == "DMASTAnd" {
                            self.expression(f(expr, "RHS"), vars, owner)
                        } else {
                            lhs
                        };
                    }
                    if lhs == Ty::Null {
                        return if kind(expr) == "DMASTAnd" {
                            Ty::Null
                        } else {
                            self.expression(f(expr, "RHS"), vars, owner)
                        };
                    }
                    if kind(expr) == "DMASTAnd" {
                        if let Ty::Nullable(inner) = &lhs {
                            if always_truthy_type(inner) {
                                let rhs = self.expression(f(expr, "RHS"), vars, owner);
                                return if rhs == Ty::Null || rhs.may_be_null() {
                                    rhs
                                } else {
                                    Ty::Nullable(Box::new(rhs))
                                };
                            }
                        }
                    }
                }
                lhs.join(&self.expression(f(expr, "RHS"), vars, owner), self.symbols)
            }
            "DMASTExpressionIn" => Ty::Num,
            _ => Ty::Unknown,
        }
    }

    fn builtin_result(
        &self,
        expr: &Value,
        name: &str,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Option<Ty> {
        let spatial = matches!(
            name,
            "view" | "oview" | "range" | "orange" | "viewers" | "oviewers" | "hearers" | "ohearers"
        );
        if !matches!(
            name,
            "min"
                | "max"
                | "block"
                | "round"
                | "text2path"
                | "image"
                | "sound"
                | "json_encode"
                | "lowertext"
                | "text2ascii"
                | "splittext"
                | "sleep"
                | "flick"
                | "turn"
                | "clamp"
                | "file"
        ) && !spatial
        {
            return None;
        }
        let args = f(expr, "Parameters").as_array()?;
        if name == "image" {
            // BYOND documents image() as returning an /image on success and
            // numeric 0 on failure. Preserve both outcomes instead of
            // claiming that the constructor is always non-null /image.
            return (args.len() <= 7).then(|| Ty::OneOf(vec![Ty::Path("/image".into()), Ty::Num]));
        }
        let fixed = match name {
            // block() enumerates turfs within two corner turfs or a 3D
            // coordinate range; the returned collection is homogeneous.
            "block" if args.len() == 2 || (3..=6).contains(&args.len()) => {
                Some(Ty::List(Box::new(Ty::Path("/turf".into()))))
            }
            "sound" if args.len() <= 5 => Some(Ty::Path("/sound".into())),
            "file" if args.len() == 1 => Some(Ty::Primitive("file".into())),
            "json_encode" if (1..=2).contains(&args.len()) => Some(Ty::Text),
            "lowertext" if args.len() == 1 => Some(Ty::Text),
            // The DM reference defines text2ascii(T, pos=1) as returning a
            // numeric character code.
            "text2ascii" if (1..=2).contains(&args.len()) => Some(Ty::Num),
            "splittext" if (2..=5).contains(&args.len()) => Some(Ty::List(Box::new(Ty::Text))),
            "sleep" if args.len() <= 1 => Some(Ty::Void),
            "flick" if args.len() == 2 => Some(Ty::Void),
            _ => None,
        };
        if matches!(
            name,
            "block"
                | "sound"
                | "file"
                | "json_encode"
                | "lowertext"
                | "text2ascii"
                | "splittext"
                | "sleep"
                | "flick"
        ) {
            return Some(fixed.unwrap_or(Ty::Unknown));
        }
        if args.iter().any(|arg| !f(arg, "Key").is_null()) {
            return Some(Ty::Unknown);
        }
        let values: Vec<Ty> = args
            .iter()
            .map(|arg| self.expression(f(arg, "Value"), vars, owner))
            .collect();
        if name == "turn" {
            return Some(if values.len() == 2 {
                match &values[0] {
                    Ty::Num => Ty::Num,
                    Ty::Primitive(icon) if icon == "icon" => Ty::Primitive("icon".into()),
                    Ty::Path(path) if path == "/matrix" || path == "/vector" => {
                        Ty::Path(path.clone())
                    }
                    _ => Ty::Unknown,
                }
            } else {
                Ty::Unknown
            });
        }
        if name == "clamp" {
            return Some(if values.len() == 3 {
                match (&values[0], &values[1], &values[2]) {
                    (Ty::Num | Ty::Null, Ty::Num, Ty::Num) => Ty::Num,
                    (Ty::Nullable(inner), Ty::Num, Ty::Num) if **inner == Ty::Num => Ty::Num,
                    (Ty::Num, low, high)
                        if [low, high]
                            .iter()
                            .all(|bound| **bound == Ty::Num || bound.has_unknown()) =>
                    {
                        // A numeric input can only produce a numeric clamped
                        // value on a successful call. Unknown bounds still
                        // need separate operand diagnostics.
                        Ty::Num
                    }
                    (Ty::Text, Ty::Text, Ty::Text) => Ty::Text,
                    (Ty::Path(value), Ty::Path(low), Ty::Path(high))
                        if value == low
                            && low == high
                            && matches!(value.as_str(), "/pixloc" | "/vector") =>
                    {
                        Ty::Path(value.clone())
                    }
                    (Ty::List(value), low, high)
                        if value.as_ref() == low
                            && low == high
                            && (matches!(value.as_ref(), Ty::Num | Ty::Text)
                                || matches!(value.as_ref(), Ty::Path(path) if matches!(path.as_str(), "/pixloc" | "/vector"))) =>
                    {
                        Ty::List(value.clone())
                    }
                    _ => Ty::Unknown,
                }
            } else {
                Ty::Unknown
            });
        }
        if spatial {
            return Some(if values.len() <= 2 {
                let result = Ty::List(Box::new(Ty::Path(
                    if matches!(name, "viewers" | "oviewers" | "hearers" | "ohearers") {
                        "/mob"
                    } else {
                        "/atom"
                    }
                    .into(),
                )));
                if matches!(name, "range" | "orange") {
                    Ty::Nullable(Box::new(result))
                } else {
                    result
                }
            } else {
                Ty::Unknown
            });
        }
        if name == "text2path" {
            return Some(if values.len() == 1 && values[0] == Ty::Text {
                Ty::Nullable(Box::new(Ty::TypePath("/".into())))
            } else {
                Ty::Unknown
            });
        }
        if name == "round" {
            // Invalid inputs are checked at the call site. When round returns,
            // its result is numeric even if an argument's source type is not
            // yet known, so uncertainty about inputs must not erase the result.
            return Some(if (1..=2).contains(&values.len()) {
                Ty::Num
            } else {
                Ty::Unknown
            });
        }
        if values.len() == 1 {
            return Some(match &values[0] {
                Ty::List(element) if element.is_precise() => {
                    Ty::Nullable(Box::new((**element).clone()))
                }
                Ty::Assoc(_, element) | Ty::Alist(_, element) if element.is_precise() => {
                    Ty::Nullable(Box::new((**element).clone()))
                }
                _ => Ty::Unknown,
            });
        }
        if values.len() >= 2 && values.iter().any(|value| value.has_unknown()) {
            for exemplar in [Ty::Num, Ty::Text] {
                if values.contains(&exemplar)
                    && values.iter().all(|value| {
                        *value == exemplar || *value == Ty::Null || value.has_unknown()
                    })
                {
                    // DM rejects mixed max/min comparison families. Unknown
                    // arguments can be null, so preserve that outcome.
                    return Some(Ty::Nullable(Box::new(exemplar)));
                }
            }
        }
        Some(
            if values.len() >= 2 && values.iter().all(|value| *value == Ty::Num) {
                Ty::Num
            } else if values.len() >= 2 && values.iter().all(|value| *value == Ty::Text) {
                Ty::Text
            } else if values.len() >= 2
                && values
                    .iter()
                    .all(|value| *value == Ty::Path("/pixloc".into()))
            {
                Ty::Path("/pixloc".into())
            } else if values.len() >= 2
                && values
                    .iter()
                    .all(|value| *value == Ty::Path("/vector".into()))
            {
                Ty::Path("/vector".into())
            } else if values.len() >= 2
                && values.iter().all(|value| {
                    matches!(value, Ty::Num | Ty::Null)
                        || matches!(value, Ty::Nullable(inner) if **inner == Ty::Num)
                })
            {
                Ty::Nullable(Box::new(Ty::Num))
            } else if values.len() >= 2
                && values.iter().all(|value| {
                    matches!(value, Ty::Text | Ty::Null)
                        || matches!(value, Ty::Nullable(inner) if **inner == Ty::Text)
                })
            {
                Ty::Nullable(Box::new(Ty::Text))
            } else {
                Ty::Unknown
            },
        )
    }

    fn signature(&self, owner: &str, name: &str) -> Option<&Signature> {
        let mut current = owner.to_owned();
        let mut seen = HashSet::new();
        loop {
            if !seen.insert(current.clone()) {
                return None;
            }
            if let Some(sig) = self.procs.get(&(current.clone(), name.into())) {
                return Some(sig);
            }
            current = self.symbols.parent(&current)?;
        }
    }

    fn preference_read_result(
        &self,
        receiver: &str,
        member: &str,
        parameters: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Option<Ty> {
        if member != "read_preference"
            || !self.symbols.is_subtype(receiver, "/datum/preferences")
            || self.signature_key(receiver, member)?
                != ("/datum/preferences".into(), "read_preference".into())
        {
            return None;
        }
        let [argument] = parameters.as_array()?.as_slice() else {
            return None;
        };
        if !f(argument, "Key").is_null() {
            return None;
        }
        let Ty::TypePath(preference) = self.expression(f(argument, "Value"), vars, owner) else {
            return None;
        };
        // read_preference populates its cache through pref_deserialize and
        // returns the validated cached value after creating a default. Keep
        // concrete overrides dynamic unless their return shape is proved.
        for (base, result) in [
            ("/datum/preference/toggle", Ty::Num),
            ("/datum/preference/numeric", Ty::Num),
            ("/datum/preference/text", Ty::Text),
            ("/datum/preference/color", Ty::Text),
        ] {
            if self.symbols.is_subtype(&preference, base)
                && self.signature_key(&preference, "pref_deserialize")?
                    == (base.into(), "pref_deserialize".into())
            {
                if base == "/datum/preference/numeric"
                    && !self
                        .signature(&preference, "create_default_value")
                        .is_some_and(|signature| signature.result == Ty::Num)
                {
                    return None;
                }
                if base == "/datum/preference/text"
                    && self.signature_key(&preference, "sanitize_input")?
                        != (base.into(), "sanitize_input".into())
                {
                    return None;
                }
                return Some(result);
            }
        }
        None
    }

    fn weakref_resolve_result(
        &self,
        receiver: &str,
        member: &str,
        parameters: &Value,
    ) -> Option<Ty> {
        if member != "resolve"
            || !self.symbols.is_subtype(receiver, "/datum/weakref")
            || self.signature_key(receiver, member)? != ("/datum/weakref".into(), "resolve".into())
            || !parameters.as_array()?.is_empty()
        {
            return None;
        }
        // resolve() returns either the located datum or null when it was
        // deleted. A subtype override is excluded by signature_key above.
        Some(Ty::Nullable(Box::new(Ty::Path("/datum".into()))))
    }

    fn tgui_input_list_result(
        &self,
        owner: &str,
        name: &str,
        parameters: &Value,
        vars: &HashMap<String, Ty>,
    ) -> Option<Ty> {
        if name != "tgui_input_list"
            || self.signature_key(owner, name)? != ("/".into(), name.into())
        {
            return None;
        }
        let parameters = parameters.as_array()?;
        // The fourth argument is `items`. Its keys are copied into the UI
        // map, and the chosen key is returned. A dismissed dialog returns null.
        let item = parameters.get(3)?;
        if parameters
            .iter()
            .take(4)
            .any(|parameter| !f(parameter, "Key").is_null())
        {
            return None;
        }
        let element = match self.expression(f(item, "Value"), vars, owner).nonnull() {
            Ty::List(element) | Ty::Assoc(element, _) | Ty::Alist(element, _) => *element,
            Ty::Record(_) => Ty::Text,
            _ => return None,
        };
        element.is_precise().then(|| with_nullable(element, true))
    }

    fn tgui_alert_result(
        &self,
        owner: &str,
        name: &str,
        parameters: &Value,
        vars: &HashMap<String, Ty>,
    ) -> Option<Ty> {
        if name != "tgui_alert" || self.signature_key(owner, name)? != ("/".into(), name.into()) {
            return None;
        }
        let parameters = parameters.as_array()?;
        // The omitted default is list("Ok"). The dialog may be dismissed,
        // leaving the implicit result null on that path.
        if parameters.len() <= 3 {
            return Some(Ty::Nullable(Box::new(Ty::Text)));
        }
        if parameters
            .iter()
            .take(4)
            .any(|parameter| !f(parameter, "Key").is_null())
        {
            return None;
        }
        let buttons = self
            .expression(f(&parameters[3], "Value"), vars, owner)
            .nonnull();
        let text_buttons = match buttons {
            Ty::List(element) | Ty::Assoc(element, _) | Ty::Alist(element, _) => {
                element.nonnull() == Ty::Text
            }
            Ty::Record(_) | Ty::EmptyList => true,
            _ => false,
        };
        text_buttons.then(|| Ty::Nullable(Box::new(Ty::Text)))
    }

    fn list2text_result(
        &self,
        owner: &str,
        name: &str,
        parameters: &Value,
        vars: &HashMap<String, Ty>,
    ) -> Option<Ty> {
        if name != "list2text" || self.signature_key(owner, name)? != ("/".into(), name.into()) {
            return None;
        }
        let arguments = parameters.as_array()?;
        let first = arguments.iter().find(|argument| {
            let key = f(argument, "Key");
            key.is_null()
                || (kind(key) == "DMASTConstantString" && f(key, "Value").as_str() == Some("ls"))
        })?;
        let input = f(first, "Value");
        let literal_items = match kind(input) {
            "DMASTList" => f(input, "Values").as_array(),
            "DMASTNewList" => f(input, "Parameters").as_array(),
            _ => None,
        };
        if let Some(items) = literal_items {
            // A list constructor has a fixed length at this call site. The
            // helper returns its sole element unchanged, but formats every
            // other length as text. Associated entries occupy one key slot.
            return match items.as_slice() {
                [] => Some(Ty::Text),
                [item] => {
                    let value = if f(item, "Key").is_null() {
                        f(item, "Value")
                    } else {
                        f(item, "Key")
                    };
                    Some(self.expression(value, vars, owner))
                }
                _ => Some(Ty::Text),
            };
        }
        let element = match self.expression(input, vars, owner).nonnull() {
            Ty::EmptyList | Ty::Record(_) => return Some(Ty::Text),
            Ty::List(element) | Ty::Assoc(element, _) | Ty::Alist(element, _) => *element,
            _ => return None,
        };
        // The singleton fast path returns the item itself. Every longer list
        // is formatted as text, and an empty list returns an empty string.
        match element {
            Ty::Text => Some(Ty::Text),
            Ty::Nullable(inner) if *inner == Ty::Text => Some(Ty::Nullable(Box::new(Ty::Text))),
            other if other.is_precise() && !other.may_be_null() => {
                Some(join_value_flow(&Ty::Text, &other, self.symbols))
            }
            _ => None,
        }
    }

    fn shape_preserving_list_result(
        &self,
        owner: &str,
        name: &str,
        parameters: &Value,
        vars: &HashMap<String, Ty>,
    ) -> Option<Ty> {
        // These repository helpers return their input list after sorting it
        // in place (sortTim) or a Copy() of it (sortList). Neither adds list
        // elements, so a proved element shape survives the call.
        if !matches!(name, "sortTim" | "sortList")
            || self.signature_key(owner, name)? != ("/".into(), name.into())
        {
            return None;
        }
        let first = parameters.as_array()?.first()?;
        let key = f(first, "Key");
        let expected = if name == "sortTim" { "to_sort" } else { "L" };
        if !(key.is_null()
            || (kind(key) == "DMASTConstantString" && f(key, "Value").as_str() == Some(expected)))
        {
            return None;
        }
        let ty = self.expression(f(first, "Value"), vars, owner).nonnull();
        (ty.is_precise() && matches!(ty, Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _)))
            .then_some(ty)
    }

    fn generic_collection_result(
        &self,
        owner: &str,
        name: &str,
        arguments: &Value,
        vars: &HashMap<String, Ty>,
    ) -> Option<Ty> {
        // Infer a small element variable from the *body*, not a helper name:
        // a one-statement proc that returns a list parameter (or its built-in
        // Copy()) transports that parameter's element type to the result.
        // The one-statement requirement excludes writes that could replace an
        // element with a different type before returning the list.
        let key = self.signature_key(owner, name)?;
        let versions = self.proc_versions.get(&key)?;
        let [signature] = versions.as_slice() else {
            return None;
        };
        if signature.result_required || signature.parameters.len() != 1 {
            return None;
        }
        if key.0 != "/"
            && self.procs.keys().any(|(candidate_owner, candidate_name)| {
                candidate_name == name
                    && candidate_owner != &key.0
                    && self.symbols.is_subtype(candidate_owner, &key.0)
            })
        {
            // A dynamically dispatched override may have a different body.
            return None;
        }
        let [(_, body)] = self.return_bodies.get(&key)?.as_slice() else {
            return None;
        };
        let [statement] = simple_statements(body)?.as_slice() else {
            return None;
        };
        if kind(statement) != "DMASTProcStatementReturn" {
            return None;
        }
        let returned = f(statement, "Value");
        let (parameter_name, copied) = if kind(returned) == "DMASTIdentifier" {
            (f(returned, "Identifier").as_str()?, false)
        } else if kind(returned) == "DMASTDereference" {
            let [operation] = f(returned, "Operations").as_array()?.as_slice() else {
                return None;
            };
            if kind(operation) != "CallOperation"
                || f(operation, "Identifier").as_str() != Some("Copy")
                || f(operation, "Safe").as_bool() == Some(true)
                || !f(operation, "Parameters").as_array()?.is_empty()
            {
                return None;
            }
            let input = f(returned, "Expression");
            if kind(input) != "DMASTIdentifier" {
                return None;
            }
            (f(input, "Identifier").as_str()?, true)
        } else {
            return None;
        };
        let index = signature
            .parameters
            .iter()
            .position(|parameter| parameter.name == parameter_name)?;
        let parameter = &signature.parameters[index];
        if !matches!(
            parameter.ty.nonnull(),
            Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _)
        ) {
            return None;
        }
        let supplied = arguments.as_array()?;
        if supplied.len() != 1 {
            // Another argument could mutate an aliased list while arguments
            // are being evaluated, before this helper returns it.
            return None;
        }
        let mut positional = 0;
        let actual = supplied.iter().find_map(|argument| {
            let argument_name = f(argument, "Key");
            let matches = if argument_name.is_null() {
                let matches = positional == index;
                positional += 1;
                matches
            } else {
                kind(argument_name) == "DMASTConstantString"
                    && f(argument_name, "Value").as_str() == Some(parameter_name)
            };
            matches.then_some(f(argument, "Value"))
        })?;
        let ty = self.expression(actual, vars, owner);
        let ty = if copied { ty.nonnull() } else { ty };
        (ty.is_precise()
            && matches!(
                ty.nonnull(),
                Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _)
            ))
        .then_some(ty)
    }

    fn inherit_override_parameter_types(&mut self) -> bool {
        let mut changed = false;
        let mut keys: Vec<_> = self.procs.keys().cloned().collect();
        keys.sort_by_key(|(owner, _)| owner.matches('/').count());
        for (owner, name) in keys {
            let Some(parent) = self.symbols.parent(&owner) else {
                continue;
            };
            let Some(parent_signature) = self.signature(&parent, &name).cloned() else {
                continue;
            };
            let key = (owner, name);
            let Some(versions) = self.proc_versions.get_mut(&key) else {
                continue;
            };
            for version in versions.iter_mut() {
                for (parameter, inherited) in version
                    .parameters
                    .iter_mut()
                    .zip(&parent_signature.parameters)
                {
                    if parameter.ty == Ty::Unknown && inherited.ty.is_precise() {
                        parameter.ty = inherited.ty.clone();
                        parameter.inferred_from_calls = inherited.inferred_from_calls;
                        changed = true;
                    }
                }
            }
            if let Some(last) = versions.last() {
                self.procs.insert(key, last.clone());
            }
        }
        changed
    }

    fn signature_key(&self, owner: &str, name: &str) -> Option<(String, String)> {
        let mut current = owner.to_owned();
        let mut seen = HashSet::new();
        loop {
            if !seen.insert(current.clone()) {
                return None;
            }
            let key = (current.clone(), name.into());
            if self.procs.contains_key(&key) {
                return Some(key);
            }
            current = self.symbols.parent(&current)?;
        }
    }

    fn validated_admin_wrapper(&self, owner: &str) -> bool {
        if owner != "/client" {
            return false;
        }
        let Some(name) = self.current_proc.as_deref() else {
            return false;
        };
        self.return_bodies
            .get(&(owner.into(), name.into()))
            .is_some_and(|bodies| {
                bodies.iter().any(|(_, body)| {
                    admin_verb_wrapper_target(name, body).is_some_and(|target| {
                        self.procs.contains_key(&(target, "__avd_do_verb".into()))
                    })
                })
            })
    }

    fn generated_admin_verb_override(&self, owner: &str, name: &str, base: &Signature) -> bool {
        if name != "__avd_do_verb"
            || base.path != "code/__defines/admin_verb.dm"
            || !base.parameters.is_empty()
        {
            return false;
        }
        let Some(suffix) = owner.strip_prefix("/datum/admin_verb/") else {
            return false;
        };
        let wrapper_name = format!("__avd_{suffix}");
        self.return_bodies
            .get(&("/client".into(), wrapper_name.clone()))
            .is_some_and(|bodies| {
                bodies.iter().any(|(_, body)| {
                    admin_verb_wrapper_target(&wrapper_name, body).as_deref() == Some(owner)
                })
            })
    }

    fn collect_call_evidence(&mut self, node: &Value, owner: &str, vars: &HashMap<String, Ty>) {
        if matches!(
            kind(node),
            "DMASTNewPath" | "DMASTNewModifiedType" | "DMASTNewExpr"
        ) {
            let path = match kind(node) {
                "DMASTNewPath" => f(f(f(node, "Path"), "Value"), "Path")
                    .as_str()
                    .map(str::to_owned),
                "DMASTNewModifiedType" => f(f(f(node, "Type"), "Value"), "Path")
                    .as_str()
                    .map(str::to_owned),
                "DMASTNewExpr" => match self.expression(f(node, "Expression"), vars, owner) {
                    Ty::TypePath(path) => Some(path),
                    _ => None,
                },
                _ => None,
            };
            if let Some(key) = path.and_then(|path| self.signature_key(&path, "New")) {
                self.record_arguments(&key, f(node, "Parameters"), owner, vars);
            }
        } else if kind(node) == "DMASTProcCall" {
            let callable = f(node, "Callable");
            if kind(callable) == "DMASTCallableProcIdentifier" {
                if let Some(name) = f(callable, "Identifier").as_str() {
                    if let Some(key) = self.signature_key(owner, name) {
                        self.record_arguments(&key, f(node, "Parameters"), owner, vars);
                    }
                }
            } else if kind(callable) == "DMASTCallableSuper" {
                if let (Some(name), Some(parent)) =
                    (self.current_proc.as_deref(), self.symbols.parent(owner))
                {
                    if self
                        .proc_versions
                        .get(&(owner.into(), name.into()))
                        .is_none_or(|versions| versions.len() == 1)
                    {
                        if let Some(key) = self.signature_key(&parent, name) {
                            let arguments = f(node, "Parameters");
                            if arguments.as_array().is_some_and(Vec::is_empty) {
                                let names: Vec<_> = self
                                    .procs
                                    .get(&(owner.into(), name.into()))
                                    .map(|signature| {
                                        signature
                                            .parameters
                                            .iter()
                                            .map(|param| param.name.clone())
                                            .collect()
                                    })
                                    .unwrap_or_default();
                                for (index, parameter) in names.iter().enumerate() {
                                    self.add_param_evidence(
                                        &key,
                                        index,
                                        vars.get(parameter).cloned().unwrap_or(Ty::Unknown),
                                    );
                                }
                            } else {
                                self.record_arguments(&key, arguments, owner, vars);
                            }
                        }
                    }
                }
            }
        } else if kind(node) == "DMASTCall" {
            let targets = self.dynamic_target_keys(node, vars, owner);
            for key in targets {
                self.record_arguments(&key, f(node, "ProcParameters"), owner, vars);
            }
        } else if kind(node) == "DMASTDereference"
            && f(node, "Operations").as_array().is_some_and(|operations| {
                operations
                    .iter()
                    .any(|operation| kind(operation) == "CallOperation")
            })
        {
            let mut receiver = self.expression(f(node, "Expression"), vars, owner);
            for op in f(node, "Operations").as_array().into_iter().flatten() {
                let member = f(op, "Identifier").as_str().unwrap_or("");
                let Ty::Path(path) = receiver.nonnull() else {
                    break;
                };
                if kind(op) == "CallOperation" {
                    if let Some(key) = self.signature_key(&path, member) {
                        self.record_arguments(&key, f(op, "Parameters"), owner, vars);
                        receiver = self.procs[&key].result.clone();
                    } else {
                        break;
                    }
                } else if kind(op) == "FieldOperation" {
                    receiver = self
                        .field_key(&path, member)
                        .and_then(|key| self.fields.get(&key))
                        .map(|field| field.ty.clone())
                        .unwrap_or(Ty::Unknown);
                } else {
                    break;
                }
            }
        }
        if let Some(fields) = node["fields"].as_object() {
            for child in fields.values() {
                if let Some(items) = child.as_array() {
                    for item in items {
                        if item.is_object() {
                            self.collect_call_evidence(item, owner, vars);
                        }
                    }
                } else if child.is_object() {
                    self.collect_call_evidence(child, owner, vars);
                }
            }
        }
    }

    fn record_inferred_constructor(
        &mut self,
        value: &Value,
        storage: &Ty,
        owner: &str,
        vars: &HashMap<String, Ty>,
    ) {
        if kind(value) != "DMASTNewInferred" {
            return;
        }
        let Ty::Path(path) = storage.nonnull() else {
            return;
        };
        if let Some(key) = self.signature_key(&path, "New") {
            self.record_arguments(&key, f(value, "Parameters"), owner, vars);
        }
    }

    fn scan_call_block(&mut self, block: &Value, owner: &str, vars: &mut HashMap<String, Ty>) {
        let Some(statements) = f(block, "Statements").as_array() else {
            return;
        };
        for statement in statements {
            match kind(statement) {
                "DMASTProcStatementVarDeclaration" => {
                    let value = f(statement, "Value");
                    let native = declared(f(statement, "Type"), f(statement, "ValueType"));
                    self.record_inferred_constructor(value, &native, owner, vars);
                    self.collect_call_evidence(value, owner, vars);
                    if let Some(name) = f(statement, "Name").as_str() {
                        let inferred = if value.is_null() {
                            if native.is_precise() {
                                with_nullable(native, true)
                            } else {
                                Ty::Null
                            }
                        } else {
                            self.expression(value, vars, owner)
                        };
                        invalidate_after(value, vars);
                        overwrite_place_fact(vars, name, inferred);
                    }
                }
                "DMASTProcStatementExpression" => {
                    let expr = f(statement, "Expression");
                    if kind(expr) == "DMASTAssign" {
                        let target = self.expression(f(expr, "LHS"), vars, owner);
                        self.record_inferred_constructor(f(expr, "RHS"), &target, owner, vars);
                    }
                    self.collect_call_evidence(expr, owner, vars);
                    if kind(expr) == "DMASTAssign" && kind(f(expr, "LHS")) == "DMASTIdentifier" {
                        if let Some(name) = f(f(expr, "LHS"), "Identifier").as_str() {
                            let actual = self.expression(f(expr, "RHS"), vars, owner);
                            invalidate_after(f(expr, "RHS"), vars);
                            if vars.contains_key(name) {
                                overwrite_place_fact(vars, name, actual);
                            }
                            continue;
                        }
                    }
                    invalidate_after(expr, vars);
                }
                "DMASTProcStatementIf" => {
                    let condition = f(statement, "Condition");
                    self.collect_call_evidence(condition, owner, vars);
                    invalidate_after(condition, vars);
                    let mut yes = vars.clone();
                    let mut no = vars.clone();
                    if !contains_unknown_effect(condition) {
                        narrow(condition, true, &mut yes);
                        narrow(condition, false, &mut no);
                    }
                    self.scan_call_block(f(statement, "Body"), owner, &mut yes);
                    if !f(statement, "ElseBody").is_null() {
                        self.scan_call_block(f(statement, "ElseBody"), owner, &mut no);
                    }
                    *vars = join_env(&yes, &no, self.symbols);
                }
                "DMASTProcStatementFor"
                | "DMASTProcStatementWhile"
                | "DMASTProcStatementDoWhile" => {
                    for header in ["Expression1", "Expression2", "Expression3", "Conditional"] {
                        let expression = f(statement, header);
                        self.collect_call_evidence(expression, owner, vars);
                        invalidate_after(expression, vars);
                    }
                    let mut body = vars.clone();
                    invalidate_after(f(statement, "Body"), &mut body);
                    self.scan_call_block(f(statement, "Body"), owner, &mut body);
                    *vars = join_env(vars, &body, self.symbols);
                }
                "DMASTProcStatementSwitch" => {
                    let value = f(statement, "Value");
                    self.collect_call_evidence(value, owner, vars);
                    invalidate_after(value, vars);
                    let mut joined = vars.clone();
                    for case in f(statement, "Cases").as_array().into_iter().flatten() {
                        let mut arm = vars.clone();
                        for choice in f(case, "Values").as_array().into_iter().flatten() {
                            self.collect_call_evidence(choice, owner, &arm);
                            invalidate_after(choice, &mut arm);
                        }
                        self.scan_call_block(f(case, "Body"), owner, &mut arm);
                        joined = join_env(&joined, &arm, self.symbols);
                    }
                    *vars = joined;
                }
                "DMASTProcStatementSpawn" => {
                    let mut deferred = vars.clone();
                    for fact in deferred.values_mut() {
                        *fact = stale_after_unknown_effect(fact);
                    }
                    deferred.insert(STALE_REFERENCES.into(), Ty::Num);
                    self.scan_call_block(f(statement, "Body"), owner, &mut deferred);
                    invalidate_after(statement, vars);
                }
                "DMASTProcStatementReturn" => {
                    self.collect_call_evidence(f(statement, "Value"), owner, vars);
                    return;
                }
                _ => self.collect_call_evidence(statement, owner, vars),
            }
        }
    }

    fn record_arguments(
        &mut self,
        key: &(String, String),
        args: &Value,
        owner: &str,
        vars: &HashMap<String, Ty>,
    ) {
        let Some(arguments) = args.as_array() else {
            return;
        };
        let Some(signature) = self.procs.get(key).cloned() else {
            return;
        };
        let mut passed = HashSet::new();
        let mut positional = 0usize;
        let mut pack = false;
        let mut current_vars = vars.clone();
        for argument in arguments {
            let value = f(argument, "Value");
            let key_node = f(argument, "Key");
            invalidate_after(key_node, &mut current_vars);
            let actual = self.expression(value, &current_vars, owner);
            invalidate_after(value, &mut current_vars);
            if kind(value) == "DMASTProcCall"
                && f(f(value, "Callable"), "Identifier").as_str() == Some("arglist")
            {
                pack = true;
                continue;
            }
            let named = key_node.as_str().or_else(|| {
                if kind(key_node) == "DMASTConstantString" {
                    f(key_node, "Value").as_str()
                } else {
                    None
                }
            });
            if !key_node.is_null() && named.is_none() {
                pack = true;
                continue;
            }
            let index = if let Some(named) = named {
                signature
                    .parameters
                    .iter()
                    .position(|param| param.name == named)
            } else {
                let index = positional;
                positional += 1;
                Some(index)
            };
            let Some(index) = index.filter(|index| *index < signature.parameters.len()) else {
                continue;
            };
            passed.insert(index);
            self.add_param_evidence(key, index, actual);
        }
        for (index, param) in signature.parameters.iter().enumerate() {
            if pack {
                self.add_param_evidence(key, index, Ty::Unknown);
            } else if !passed.contains(&index) && !param.has_default {
                self.add_param_evidence(key, index, Ty::Null);
            }
        }
    }

    fn add_param_evidence(&mut self, key: &(String, String), index: usize, actual: Ty) {
        let evidence = self
            .param_evidence
            .entry((key.0.clone(), key.1.clone(), index))
            .or_insert_with(|| ParamEvidence {
                ty: if actual.has_unknown() {
                    Ty::Unknown
                } else {
                    actual.clone()
                },
                calls: 0,
                unresolved: 0,
                conflict: false,
                constraint: None,
                constraint_sites: 0,
            });
        evidence.calls += 1;
        if actual.has_unknown() {
            evidence.unresolved += 1;
        } else if evidence.ty == Ty::Unknown {
            evidence.ty = actual;
        } else {
            let joined = evidence.ty.join(&actual, self.symbols);
            if joined == Ty::Unknown || matches!(joined, Ty::OneOf(_)) {
                evidence.conflict = true;
            }
            evidence.ty = joined;
        }
    }

    fn record_parameter_constraints(&mut self, body: &Value, owner: &str, name: &str) {
        let key = (owner.to_owned(), name.to_owned());
        let Some(signature) = self.procs.get(&key) else {
            return;
        };
        let mut locals = HashSet::new();
        collect_local_names(body, &mut locals);
        let parameters: HashMap<_, _> = signature
            .parameters
            .iter()
            .enumerate()
            .filter(|(_, param)| !locals.contains(&param.name))
            .map(|(index, param)| (param.name.clone(), index))
            .collect();
        let mut uses = Vec::new();
        numeric_parameter_uses(body, &parameters, &mut uses);
        for index in uses {
            let entry = self
                .param_evidence
                .entry((key.0.clone(), key.1.clone(), index))
                .or_insert_with(|| ParamEvidence {
                    ty: Ty::Unknown,
                    calls: 0,
                    unresolved: 0,
                    conflict: false,
                    constraint: None,
                    constraint_sites: 0,
                });
            entry.constraint = Some(Ty::Num);
            entry.constraint_sites += 1;
        }
    }

    fn parent_signature(&self, owner: &str, name: &str) -> Option<&Signature> {
        if let Some(versions) = self.proc_versions.get(&(owner.into(), name.into())) {
            if versions.len() > 1 {
                let index = self.current_proc_version?;
                if index > 0 {
                    return versions.get(index - 1);
                }
            }
        }
        let parent = self.symbols.parent(owner)?;
        let key = self.signature_key(&parent, name)?;
        self.proc_versions
            .get(&key)
            .and_then(|versions| versions.last())
            .or_else(|| self.procs.get(&key))
    }

    fn dynamic_signature(
        &self,
        expr: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Option<Signature> {
        let args = f(expr, "CallParameters").as_array()?;
        if args.len() == 1 {
            let mut reference_expr = f(&args[0], "Value");
            while kind(reference_expr) == "DMASTExpressionWrapped" {
                reference_expr = f(reference_expr, "Value");
            }
            if kind(reference_expr) != "DMASTConstantPath" {
                return None;
            }
            let reference = self.expression(reference_expr, vars, owner);
            let Ty::TypePath(path) = reference else {
                return None;
            };
            let (receiver, name) = path
                .rsplit_once("/proc/")
                .or_else(|| path.rsplit_once("/verb/"))?;
            let receiver = if receiver.is_empty() { "/" } else { receiver };
            if self
                .symbols
                .duplicate_procs
                .contains(&(receiver.into(), name.into()))
            {
                return None;
            }
            return self.procs.get(&(receiver.into(), name.into())).cloned();
        }
        if args.len() != 2 {
            return None;
        }
        let target = self.expression(f(&args[0], "Value"), vars, owner);
        let name_expr = f(&args[1], "Value");
        let names = finite_literal_names(name_expr)?;
        let Ty::Path(receiver) = target else {
            return None;
        };
        let mut resolved: Option<Signature> = None;
        for name in names {
            let key = self.signature_key(&receiver, name)?;
            if self.symbols.duplicate_procs.contains(&key) {
                return None;
            }
            let signature = self.procs.get(&key)?.clone();
            if let Some(previous) = &resolved {
                if previous.result != signature.result
                    || previous.result_required != signature.result_required
                    || previous.parameters.len() != signature.parameters.len()
                    || previous
                        .parameters
                        .iter()
                        .zip(&signature.parameters)
                        .any(|(left, right)| {
                            left.name != right.name
                                || left.ty != right.ty
                                || left.has_default != right.has_default
                        })
                {
                    return None;
                }
            } else {
                resolved = Some(signature);
            }
        }
        resolved
    }

    fn dynamic_target_keys(
        &self,
        expr: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Vec<(String, String)> {
        if self.dynamic_signature(expr, vars, owner).is_none() {
            return Vec::new();
        }
        let Some(args) = f(expr, "CallParameters").as_array() else {
            return Vec::new();
        };
        if args.len() == 1 {
            let mut reference = f(&args[0], "Value");
            while kind(reference) == "DMASTExpressionWrapped" {
                reference = f(reference, "Value");
            }
            let Ty::TypePath(path) = self.expression(reference, vars, owner) else {
                return Vec::new();
            };
            let Some((receiver, name)) = path
                .rsplit_once("/proc/")
                .or_else(|| path.rsplit_once("/verb/"))
            else {
                return Vec::new();
            };
            let receiver = if receiver.is_empty() { "/" } else { receiver };
            return vec![(receiver.into(), name.into())];
        }
        if args.len() == 2 {
            let Ty::Path(receiver) = self.expression(f(&args[0], "Value"), vars, owner) else {
                return Vec::new();
            };
            return finite_literal_names(f(&args[1], "Value"))
                .into_iter()
                .flatten()
                .filter_map(|name| self.signature_key(&receiver, name))
                .collect();
        }
        Vec::new()
    }

    fn type_enumeration_result(&self, expr: &Value, vars: &HashMap<String, Ty>, owner: &str) -> Ty {
        let Some(parameters) = f(expr, "Parameters").as_array() else {
            return Ty::Unknown;
        };
        let mut element: Option<Ty> = None;
        for parameter in parameters {
            if !f(parameter, "Key").is_null() {
                return Ty::Unknown;
            }
            let Ty::TypePath(path) = self.expression(f(parameter, "Value"), vars, owner) else {
                return Ty::Unknown;
            };
            element = Some(match element {
                Some(previous) => previous.join(&Ty::TypePath(path), self.symbols),
                None => Ty::TypePath(path),
            });
        }
        element
            .map(|element| Ty::List(Box::new(element)))
            .unwrap_or(Ty::Unknown)
    }

    fn register(&mut self, item: &Value) {
        let owner = item["owner"].as_str().unwrap_or("");
        let name = item["name"].as_str().unwrap_or("");
        if item["kind"] == "field" {
            if self.strict(item) {
                for conflict in conflicting_contracts(
                    self.contracts,
                    owner,
                    name,
                    None,
                    Visibility::TypeHint,
                    true,
                ) {
                    self.findings
                        .push(issue(item, "conflicting-type-contract", conflict));
                }
            }
            let mut native = declared(&item["type"], &item["valueType"]);
            if native == Ty::Unknown {
                if let Some(builtin) = builtin_field_type(owner, name) {
                    native = builtin;
                }
            }
            let hint = annotated_type(self.contracts, owner, name, Visibility::TypeHint, None);
            let is_nullable = nullable(self.contracts, owner, name, None)
                || matches!(&hint, Some(Ty::Nullable(_)))
                || matches!(&native, Ty::Nullable(_));
            let explicit_type = hint.is_some() || native != Ty::Unknown;
            let ty = with_nullable(hint.unwrap_or(native), is_nullable);
            let evidence = if !ty.has_unknown()
                && self.literal_collection_accepts(&ty, &item["initializer"], owner)
            {
                ty.nonnull()
            } else {
                self.expression(&item["initializer"], &HashMap::new(), owner)
            };
            let evidence = if item["initializer"].is_null() {
                Ty::Null
            } else {
                evidence
            };
            let key = (owner.into(), name.into());
            let phase = annotation(self.contracts, owner, name, Visibility::InitializedBy, None)
                .and_then(|contract| contract.value.clone());
            let delayed = phase.is_some();
            self.fields
                .entry(key)
                .and_modify(|f| {
                    f.evidence = f.evidence.join(&evidence, self.symbols);
                })
                .or_insert_with(|| FieldInfo {
                    ty,
                    explicit_type,
                    evidence,
                    origin: item.clone(),
                    nullable: is_nullable,
                    delayed,
                    phase,
                    proved_initialization: false,
                    initially_null: !(name == "type"
                        && matches!(
                            item["file"].as_str(),
                            Some("Types/Datum.dm" | "Types/Client.dm")
                        ))
                        && (item["initializer"].is_null()
                            || kind(&item["initializer"]) == "DMASTConstantNull"),
                    saw_unknown_write: false,
                    conflict: false,
                });
        } else if item["kind"] == "field-override" {
            self.overrides.push(item.clone());
        } else if item["kind"] == "proc" {
            if self.strict(item) {
                for conflict in conflicting_contracts(
                    self.contracts,
                    owner,
                    name,
                    None,
                    Visibility::ReturnType,
                    false,
                ) {
                    self.findings
                        .push(issue(item, "conflicting-type-contract", conflict));
                }
                for param in item["parameters"].as_array().into_iter().flatten() {
                    let param_name = param["Name"].as_str().unwrap_or("");
                    for conflict in conflicting_contracts(
                        self.contracts,
                        owner,
                        name,
                        Some(param_name),
                        Visibility::ParamType,
                        false,
                    ) {
                        self.findings.push(issue(
                            item,
                            "conflicting-type-contract",
                            format!("parameter {param_name}: {conflict}"),
                        ));
                    }
                }
                for local in self.contracts.iter().filter(|contract| {
                    contract.owner == owner
                        && contract.member == name
                        && contract.visibility == Visibility::LocalType
                }) {
                    for conflict in conflicting_contracts(
                        self.contracts,
                        owner,
                        name,
                        local.parameter.as_deref(),
                        Visibility::LocalType,
                        false,
                    ) {
                        self.findings.push(issue(
                            item,
                            "conflicting-type-contract",
                            format!(
                                "local {}: {conflict}",
                                local.parameter.as_deref().unwrap_or("")
                            ),
                        ));
                    }
                }
            }
            if matches!(
                name,
                "isnull"
                    | "islist"
                    | "isnum"
                    | "istext"
                    | "ispath"
                    | "text2path"
                    | "QDELETED"
                    | "min"
                    | "max"
                    | "round"
                    | "view"
                    | "oview"
                    | "range"
                    | "orange"
                    | "viewers"
                    | "oviewers"
                    | "hearers"
                    | "ohearers"
            ) && item["file"].as_str() != Some("_Standard.dm")
            {
                self.findings.push(issue(
                    item,
                    "shadowed-type-guard",
                    format!("{owner}/{name} shadows a builtin whose effects type flow relies on; rename it"),
                ));
            }
            if name == "New" && item["parameters"].as_array().is_some_and(Vec::is_empty) {
                self.new_bodies.insert(owner.into(), item["body"].clone());
            }
            let params = item["parameters"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|param| {
                    let param_name = param["Name"].as_str().unwrap_or("");
                    let native = declared(&param["type"], &param["valueType"]);
                    let engine_topic = if name == "Topic"
                        && (self.symbols.is_subtype(owner, "/datum")
                            || self.symbols.is_subtype(owner, "/client"))
                    {
                        match param_name {
                            "href" => Some(Ty::Text),
                            "href_list" => Some(Ty::Assoc(Box::new(Ty::Text), Box::new(Ty::Text))),
                            "hsrc" if self.symbols.is_subtype(owner, "/client") => {
                                Some(Ty::Nullable(Box::new(Ty::Path("/datum".into()))))
                            }
                            _ => None,
                        }
                    } else {
                        None
                    };
                    let hint = annotated_type(
                        self.contracts,
                        owner,
                        name,
                        Visibility::ParamType,
                        Some(param_name),
                    );
                    ParamInfo {
                        name: param_name.into(),
                        ty: with_nullable(
                            hint.or(engine_topic).unwrap_or(native),
                            nullable(self.contracts, owner, name, Some(param_name)),
                        ),
                        has_default: !param["defaultValue"].is_null(),
                        default_ty: if param["defaultValue"].is_null() {
                            Ty::Unknown
                        } else {
                            self.expression(&param["defaultValue"], &HashMap::new(), owner)
                        },
                        inferred_from_calls: false,
                    }
                })
                .collect();
            let explicit =
                annotated_type(self.contracts, owner, name, Visibility::ReturnType, None);
            let (result, result_required) = if let Some(ty) = explicit {
                (
                    with_nullable(ty, nullable(self.contracts, owner, name, None)),
                    true,
                )
            } else if self
                .symbols
                .duplicate_procs
                .contains(&(owner.into(), name.into()))
            {
                let declared = declared(&Value::Null, &item["returnType"]);
                (declared.clone(), declared.is_precise())
            } else if let Some(symbol) = self.symbols.proc(owner, name) {
                (
                    Ty::parse(&symbol.return_kind),
                    symbol.return_kind != "unknown",
                )
            } else {
                (Ty::Unknown, false)
            };
            let signature = Signature {
                parameters: params,
                result,
                result_required,
                inferred_nullable_result: false,
                path: source(item).0,
                line: source(item).1,
            };
            let key = (owner.into(), name.into());
            let versions = self.proc_versions.entry(key.clone()).or_default();
            let version = versions.len();
            versions.push(signature.clone());
            if self.strict(item) {
                self.return_bodies
                    .entry(key.clone())
                    .or_default()
                    .push((version, item["body"].clone()));
            }
            self.procs.insert(key, signature);
        }
    }

    fn simple_branch_local_facts(
        &self,
        body: &Value,
        owner: &str,
        mut facts: HashMap<String, Ty>,
        locals: &HashSet<String>,
    ) -> Option<HashMap<String, Ty>> {
        if body.is_null() {
            return Some(facts);
        }
        for statement in simple_statements(body)? {
            if kind(statement) != "DMASTProcStatementExpression" {
                return None;
            }
            let expression = f(statement, "Expression");
            if kind(expression) != "DMASTAssign" {
                return None;
            }
            let lhs = f(expression, "LHS");
            let name = f(lhs, "Identifier").as_str()?;
            if kind(lhs) != "DMASTIdentifier" || !locals.contains(name) {
                return None;
            }
            let rhs = f(expression, "RHS");
            if contains_unknown_effect(rhs) || contains_mutation(rhs) {
                return None;
            }
            let actual = self.expression(rhs, &facts, owner);
            overwrite_place_fact(&mut facts, name, actual);
        }
        Some(facts)
    }

    fn simple_if_local_facts(
        &self,
        statement: &Value,
        owner: &str,
        facts: &HashMap<String, Ty>,
        locals: &HashSet<String>,
    ) -> Option<HashMap<String, Ty>> {
        if kind(statement) != "DMASTProcStatementIf" {
            return None;
        }
        let condition = f(statement, "Condition");
        if contains_unknown_effect(condition) || contains_mutation(condition) {
            return None;
        }
        let mut yes = facts.clone();
        let mut no = facts.clone();
        narrow(condition, true, &mut yes);
        narrow(condition, false, &mut no);
        let yes = self.simple_branch_local_facts(f(statement, "Body"), owner, yes, locals)?;
        let no = self.simple_branch_local_facts(f(statement, "ElseBody"), owner, no, locals)?;
        Some(join_env(&yes, &no, self.symbols))
    }

    fn register_writes(
        &mut self,
        node: &Value,
        owner: &str,
        vars: &HashMap<String, Ty>,
        locals: &HashSet<String>,
    ) {
        if kind(node) == "DMASTNewModifiedType" {
            if let Some(path) = f(f(f(node, "Type"), "Value"), "Path").as_str() {
                for entry in f(f(node, "Type"), "VarOverridesAst")
                    .as_array()
                    .into_iter()
                    .flatten()
                {
                    if let Some(name) = entry["name"].as_str() {
                        let assignment = serde_json::json!({"kind":"DMASTAssign","fields":{
                            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":name}},
                            "RHS":entry["value"]
                        }});
                        self.register_writes(&assignment, path, vars, &HashSet::new());
                    }
                }
            }
        }
        if kind(node) == "DMASTProcBlockInner" {
            let mut current = vars.clone();
            for statement in f(node, "Statements").as_array().into_iter().flatten() {
                self.register_writes(statement, owner, &current, locals);
                if kind(statement) == "DMASTProcStatementReturn"
                    || (kind(statement) == "DMASTProcStatementIf"
                        && simple_block_returns(f(statement, "Body"))
                        && simple_block_returns(f(statement, "ElseBody")))
                {
                    break;
                }
                if kind(statement) == "DMASTProcStatementVarDeclaration" {
                    if let Some(name) = f(statement, "Name").as_str() {
                        let initializer = f(statement, "Value");
                        let native = declared(f(statement, "Type"), f(statement, "ValueType"));
                        let actual = if initializer.is_null() {
                            Ty::Null
                        } else {
                            self.expression(initializer, &current, owner)
                        };
                        invalidate_after(initializer, &mut current);
                        let fact = if actual == Ty::Null && native.is_precise() {
                            with_nullable(native.clone(), true)
                        } else if actual.is_precise() || matches!(actual, Ty::Nullable(_)) {
                            actual
                        } else {
                            Ty::Unknown
                        };
                        overwrite_place_fact(&mut current, name, fact);
                    }
                } else if kind(statement) == "DMASTProcStatementExpression" {
                    let expression = f(statement, "Expression");
                    let mut assigned_local = false;
                    if kind(expression) == "DMASTAssign"
                        && kind(f(expression, "LHS")) == "DMASTIdentifier"
                    {
                        if let Some(name) = f(f(expression, "LHS"), "Identifier").as_str() {
                            if locals.contains(name) {
                                let rhs = f(expression, "RHS");
                                let actual = self.expression(rhs, &current, owner);
                                invalidate_after(rhs, &mut current);
                                overwrite_place_fact(&mut current, name, actual);
                                assigned_local = true;
                            }
                        }
                    }
                    if !assigned_local {
                        invalidate_after(expression, &mut current);
                    }
                } else {
                    let joined = self.simple_if_local_facts(statement, owner, &current, locals);
                    invalidate_after(statement, &mut current);
                    if matches!(
                        kind(statement),
                        "DMASTProcStatementIf"
                            | "DMASTProcStatementSwitch"
                            | "DMASTProcStatementFor"
                            | "DMASTProcStatementWhile"
                            | "DMASTProcStatementDoWhile"
                    ) {
                        // A branch only erases storage evidence for bindings
                        // that it may assign. Retain declared parameter and
                        // local receiver types when unrelated control flow
                        // precedes a field write.
                        let mut writes = LocalWrites::default();
                        collect_local_writes(statement, &mut writes);
                        current.retain(|name, _| {
                            !writes.writes.contains_key(name)
                                && !writes.unsafe_writes.contains(name)
                        });
                        if let Some(joined) = joined {
                            current = joined;
                        }
                    }
                }
            }
            return;
        }
        if kind(node) == "DMASTProcStatementIf" {
            let condition = f(node, "Condition");
            self.register_writes(condition, owner, vars, locals);
            let mut yes = vars.clone();
            invalidate_after(condition, &mut yes);
            if !contains_unknown_effect(condition) {
                narrow(condition, true, &mut yes);
            }
            self.register_writes(f(node, "Body"), owner, &yes, locals);
            let mut no = vars.clone();
            invalidate_after(condition, &mut no);
            if !contains_unknown_effect(condition) {
                narrow(condition, false, &mut no);
            }
            self.register_writes(f(node, "ElseBody"), owner, &no, locals);
            return;
        }
        if kind(node) == "DMASTProcStatementSwitch" {
            let mut arm = vars.clone();
            let value = f(node, "Value");
            self.register_writes(value, owner, &arm, locals);
            invalidate_after(value, &mut arm);
            for case in f(node, "Cases").as_array().into_iter().flatten() {
                let mut case_vars = arm.clone();
                for choice in f(case, "Values").as_array().into_iter().flatten() {
                    self.register_writes(choice, owner, &case_vars, locals);
                    invalidate_after(choice, &mut case_vars);
                }
                invalidate_after(f(case, "Body"), &mut case_vars);
                self.register_writes(f(case, "Body"), owner, &case_vars, locals);
            }
            return;
        }
        if kind(node) == "DMASTProcStatementSpawn" {
            let mut deferred = vars.clone();
            for fact in deferred.values_mut() {
                *fact = stale_after_unknown_effect(fact);
            }
            deferred.insert(STALE_REFERENCES.into(), Ty::Num);
            self.register_writes(f(node, "Body"), owner, &deferred, locals);
            return;
        }
        if matches!(
            kind(node),
            "DMASTProcStatementFor" | "DMASTProcStatementWhile" | "DMASTProcStatementDoWhile"
        ) {
            let mut body = vars.clone();
            // Field-write inference must not reuse facts that a loop header (or
            // an earlier iteration) can invalidate through an unknown call.
            for header in ["Expression1", "Expression2", "Expression3", "Conditional"] {
                let expression = f(node, header);
                self.register_writes(expression, owner, &body, locals);
                invalidate_after(expression, &mut body);
            }
            // A later iteration starts after every effect in the preceding
            // iteration, so body effects also constrain its entry facts.
            invalidate_after(f(node, "Body"), &mut body);
            if let Some((name, declared)) = iterator_declaration(f(f(node, "Expression1"), "LHS")) {
                body.insert(name, declared);
            }
            self.register_writes(f(node, "Body"), owner, &body, locals);
            return;
        }
        if matches!(kind(node), "DMASTAssign" | "DMASTAppend") {
            let lhs = f(node, "LHS");
            let rhs = f(node, "RHS");
            if kind(node) == "DMASTAssign" {
                if let Some((key, index_ty)) = self.indexed_field_key(lhs, vars, owner, locals) {
                    let index = f(
                        f(lhs, "Operations")
                            .as_array()
                            .and_then(|ops| ops.first())
                            .unwrap_or(&Value::Null),
                        "Index",
                    );
                    let literal_key = (kind(index) == "DMASTConstantString")
                        .then(|| f(index, "Value").as_str())
                        .flatten();
                    if self.merge_keyed_field_write(&key, literal_key, rhs, vars, owner) {
                        self.register_writes(f(index, "Index"), owner, vars, locals);
                        self.register_writes(rhs, owner, vars, locals);
                        return;
                    }
                    let field = &self.fields[&key];
                    let list_ty = field.ty.nonnull();
                    if matches!(list_ty, Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _))
                        || matches!(
                            field.evidence,
                            Ty::EmptyList
                                | Ty::EmptyAlist
                                | Ty::List(_)
                                | Ty::Assoc(_, _)
                                | Ty::Alist(_, _)
                        )
                    {
                        let element = self.expression(rhs, vars, owner);
                        let element = if element.has_unknown()
                            && self.numeric_index_recurrence(rhs, &key, vars, owner)
                        {
                            Ty::Num
                        } else {
                            element
                        };
                        let value = if element.is_precise() {
                            match index_ty {
                                Ty::Text if matches!(list_ty, Ty::Alist(_, _)) => {
                                    Ty::Alist(Box::new(Ty::Text), Box::new(element))
                                }
                                Ty::Text => Ty::Assoc(Box::new(Ty::Text), Box::new(element)),
                                Ty::Nullable(inner) if *inner == Ty::Text => {
                                    Ty::Assoc(Box::new(Ty::Nullable(inner)), Box::new(element))
                                }
                                Ty::Num if matches!(list_ty, Ty::Alist(_, _)) => {
                                    Ty::Alist(Box::new(Ty::Num), Box::new(element))
                                }
                                Ty::Num => Ty::List(Box::new(element)),
                                _ => Ty::Unknown,
                            }
                        } else {
                            Ty::Unknown
                        };
                        self.profile_field_write(&key, &value, node, owner);
                        self.merge_field_write(&key, value);
                    }
                }
            }
            let target = if let Some(key) = self.reflected_field_key(lhs, vars, owner) {
                Some(key)
            } else if kind(lhs) == "DMASTIdentifier" {
                f(lhs, "Identifier")
                    .as_str()
                    .filter(|name| !locals.contains(*name))
                    .and_then(|name| self.field_key(owner, name))
            } else if kind(lhs) == "DMASTDereference" {
                let operations = f(lhs, "Operations").as_array();
                if let Some(op) = operations
                    .filter(|ops| ops.len() == 1)
                    .and_then(|ops| ops.first())
                {
                    let receiver = self.expression(f(lhs, "Expression"), vars, owner).nonnull();
                    if let (Ty::Path(target), "FieldOperation", Some(member)) =
                        (receiver, kind(op), f(op, "Identifier").as_str())
                    {
                        self.field_key(&target, member)
                    } else {
                        None
                    }
                } else {
                    None
                }
            } else {
                None
            };
            if let Some(key) = target {
                let field_type = self.fields[&key].ty.clone();
                let value = if kind(node) == "DMASTAppend" {
                    let existing = &self.fields[&key].evidence;
                    if matches!(field_type.nonnull(), Ty::List(_))
                        || matches!(existing, Ty::EmptyList | Ty::List(_))
                    {
                        let element = self.expression(rhs, vars, owner);
                        if element.is_precise() && !element.may_be_null() {
                            Some(match element {
                                Ty::List(inner) => Ty::List(inner),
                                other => Ty::List(Box::new(other)),
                            })
                        } else {
                            Some(Ty::Unknown)
                        }
                    } else {
                        None
                    }
                } else if !field_type.has_unknown()
                    && self.literal_collection_accepts(&field_type, rhs, owner)
                {
                    Some(field_type.nonnull())
                } else if kind(rhs) == "DMASTNewInferred"
                    && matches!(field_type.nonnull(), Ty::Path(_))
                {
                    // `new()` takes its concrete path from the typed target.
                    Some(field_type.nonnull())
                } else {
                    Some(self.expression(rhs, vars, owner))
                };
                if let Some(value) = value {
                    self.profile_field_write(&key, &value, node, owner);
                    self.merge_field_write(&key, value);
                }
            }
        }
        if let Some(map) = node["fields"].as_object() {
            for child in map.values() {
                if let Some(array) = child.as_array() {
                    for item in array {
                        if item.is_object() {
                            self.register_writes(item, owner, vars, locals);
                        }
                    }
                } else if child.is_object() {
                    self.register_writes(child, owner, vars, locals);
                }
            }
        }
    }

    fn merge_field_write(&mut self, key: &(String, String), value: Ty) {
        let field = self.fields.get_mut(key).expect("field key resolved");
        if value.has_unknown()
            && !matches!(
                (&value, field.ty.nonnull()),
                (Ty::EmptyList, Ty::EmptyList | Ty::List(_) | Ty::Assoc(_, _))
                    | (Ty::EmptyAlist, Ty::EmptyAlist | Ty::Alist(_, _))
            )
        {
            field.saw_unknown_write = true;
        } else if field.evidence == Ty::Null {
            field.evidence = value;
        } else {
            let joined = join_value_flow(&field.evidence, &value, self.symbols);
            if (joined.has_unknown() || matches!(joined, Ty::OneOf(_)))
                && field.evidence.is_precise()
                && value.is_precise()
            {
                field.conflict = true;
            }
            field.evidence = joined;
        }
    }

    // `values[key] = (values[key] || 0) + amount` has a numeric fixed point
    // when the list starts empty. OpenDream expands LAZYACCESS into nested
    // ternaries, so prove every value branch numeric and require the old
    // value plus a numeric-zero fallback. Other writes still join normally.
    fn numeric_index_recurrence(
        &self,
        rhs: &Value,
        field_key: &(String, String),
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> bool {
        if !matches!(
            self.fields[field_key].evidence,
            Ty::EmptyList | Ty::List(_) | Ty::Assoc(_, _)
        ) || contains_unknown_effect(rhs)
        {
            return false;
        }
        let Some((old_value, zero_fallback)) =
            self.numeric_index_component(rhs, field_key, vars, owner)
        else {
            return false;
        };
        old_value && zero_fallback
    }

    fn numeric_index_component(
        &self,
        expr: &Value,
        field_key: &(String, String),
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Option<(bool, bool)> {
        if numeric_operand(&self.expression(expr, vars, owner)) {
            let zero = matches!(kind(expr), "DMASTConstantInteger" | "DMASTConstantFloat")
                && f(expr, "Value").as_f64() == Some(0.0);
            return Some((false, zero));
        }
        match kind(expr) {
            "DMASTExpressionWrapped" => {
                self.numeric_index_component(f(expr, "Value"), field_key, vars, owner)
            }
            "DMASTAdd" | "DMASTOr" => {
                let left = self.numeric_index_component(f(expr, "LHS"), field_key, vars, owner)?;
                let right = self.numeric_index_component(f(expr, "RHS"), field_key, vars, owner)?;
                Some((left.0 || right.0, left.1 || right.1))
            }
            "DMASTTernary" if !contains_unknown_effect(f(expr, "A")) => {
                let yes = self.numeric_index_component(f(expr, "B"), field_key, vars, owner)?;
                let no = self.numeric_index_component(f(expr, "C"), field_key, vars, owner)?;
                Some((yes.0 || no.0, yes.1 || no.1))
            }
            "DMASTDereference" => {
                let base = f(expr, "Expression");
                let base = if kind(base) == "DMASTExpressionWrapped" {
                    f(base, "Value")
                } else {
                    base
                };
                let name = f(base, "Identifier").as_str()?;
                if kind(base) == "DMASTIdentifier"
                    && self.field_key(owner, name).as_ref() == Some(field_key)
                    && f(expr, "Operations")
                        .as_array()
                        .is_some_and(|ops| ops.len() == 1 && kind(&ops[0]) == "IndexOperation")
                {
                    Some((true, false))
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    fn merge_keyed_field_write(
        &mut self,
        field_key: &(String, String),
        literal_key: Option<&str>,
        rhs: &Value,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> bool {
        let field = &self.fields[field_key];
        // A list with independently typed literal keys is a record. Only an
        // empty list or an existing record may enter this model: an ordinary
        // homogeneous list could have other writers and values at these keys.
        if !matches!(field.evidence, Ty::EmptyList | Ty::Record(_))
            || (field.explicit_type && field.ty.is_precise() && !matches!(field.ty, Ty::Record(_)))
        {
            return false;
        }
        if literal_key.is_none()
            && !matches!(field.evidence, Ty::Record(_))
            && !matches!(field.ty, Ty::Record(_))
        {
            return false;
        }
        let Some(name) = literal_key else {
            // A computed key could overwrite any record member.
            let field = self.fields.get_mut(field_key).expect("field key resolved");
            field.evidence = Ty::Unknown;
            field.saw_unknown_write = true;
            return true;
        };
        let value = self.expression(rhs, vars, owner);
        let field = self.fields.get_mut(field_key).expect("field key resolved");
        let mut members = match &field.evidence {
            Ty::Record(members) => members.clone(),
            _ => BTreeMap::new(),
        };
        let member = members.entry(name.into()).or_insert((value.clone(), true));
        let joined = join_value_flow(&member.0, &value, self.symbols);
        if joined.has_unknown() && member.0.is_precise() && value.is_precise() {
            field.conflict = true;
        }
        member.0 = joined;
        field.saw_unknown_write |= value.has_unknown();
        field.evidence = Ty::Record(members);
        true
    }

    fn profile_field_write(&self, key: &(String, String), value: &Ty, node: &Value, owner: &str) {
        if std::env::var_os("DM_HEALTH_PROFILE").is_none() {
            return;
        }
        static DESC_REPORTED: std::sync::atomic::AtomicBool =
            std::sync::atomic::AtomicBool::new(false);
        static ICON_REPORTED: std::sync::atomic::AtomicBool =
            std::sync::atomic::AtomicBool::new(false);
        let reported = match (key.0.as_str(), key.1.as_str()) {
            ("/atom", "desc") => &DESC_REPORTED,
            ("/mob/living/simple_mob", "icon_living") => &ICON_REPORTED,
            _ => return,
        };
        let prior = &self.fields[key].evidence;
        if value.has_unknown() || !prior.is_precise() {
            return;
        }
        let joined = join_value_flow(prior, value, self.symbols);
        if !joined.has_unknown() && !matches!(joined.nonnull(), Ty::OneOf(_)) {
            return;
        }
        if reported.swap(true, std::sync::atomic::Ordering::Relaxed) {
            return;
        }
        let (path, line) = source(node);
        let proc_name = PROFILE_WRITE_PROC.with(|name| name.borrow().clone());
        eprintln!(
            "dm-health field inference conflict: field={}.{} writer_owner={} writer_proc={} source={}:{} prior={} rhs={} join={}",
            key.0,
            key.1,
            owner,
            proc_name.as_deref().unwrap_or("<unavailable>"),
            path,
            line,
            prior.label(),
            value.label(),
            joined.label(),
        );
    }

    fn finalize_fields(&mut self) {
        self.infer_field_types();
        for ((owner, name), field) in &mut self.fields {
            let strict = self.selection.includes(source(&field.origin).0.as_str());
            if !strict {
                continue;
            }
            self.coverage.strict_declarations += 1;
            if !field.ty.is_precise() || field.conflict {
                self.coverage.unresolved_declarations += 1;
                if !field.ty.is_precise() {
                    self.findings.push(issue(
                        &field.origin,
                        "unknown-field-type",
                        format!("{owner}.{name} has no proven precise single type"),
                    ));
                }
            } else {
                self.coverage.known_declarations += 1;
            }
            if field.conflict {
                self.findings.push(issue(
                    &field.origin,
                    "field-type-conflict",
                    format!("{owner}.{name} receives unrelated types"),
                ));
            }
            if !field.explicit_type
                && matches!(&field.ty, Ty::Path(path) if ["/datum", "/atom", "/atom/movable"].contains(&path.as_str()))
            {
                self.findings.push(issue(
                    &field.origin,
                    "broad-inferred-field-type",
                    format!("{owner}.{name} needs an explicit broad type contract"),
                ));
            }
            if field.saw_unknown_write {
                self.findings.push(issue(
                    &field.origin,
                    "unknown-field-write",
                    format!("{owner}.{name} has a write whose type cannot be proved"),
                ));
            }
            if field.initially_null
                && !field.nullable
                && !field.delayed
                && !field.proved_initialization
            {
                self.findings.push(issue(&field.origin, "required-field-uninitialized", format!("{owner}.{name} starts null; annotate nullable or prove initialization before publication")));
            }
            if field.initially_null
                && field.delayed
                && !field.nullable
                && !field.proved_initialization
            {
                let phase = field.phase.as_deref().unwrap_or("<unspecified>");
                let reason = if self.symbols.is_subtype(owner, "/atom") && phase == "Initialize" {
                    "atom Initialize can be deferred during map loading; assignment before every ordinary read or publication is not proved"
                } else if self.symbols.is_subtype(owner, "/atom") && phase == "New" {
                    "atom New does not establish the delayed Initialize lifecycle; assignment before every ordinary read or publication is not proved"
                } else {
                    "assignment before publication is not proved"
                };
                self.findings.push(issue(
                    &field.origin,
                    "unproven-initialization",
                    format!("{owner}.{name} declares initialized-by {phase}, but {reason}"),
                ));
            }
        }
    }

    fn infer_field_types(&mut self) -> bool {
        let mut changed = false;
        for field in self.fields.values_mut() {
            if field.explicit_type && field.ty.is_precise() {
                continue;
            }
            let inferred = if field.evidence == Ty::Null {
                Ty::Unknown
            } else {
                field.evidence.nonnull()
            };
            let empty_list_gains_elements = matches!(
                (&field.ty, &inferred),
                (Ty::EmptyList, Ty::List(_) | Ty::Assoc(_, _) | Ty::Record(_))
                    | (Ty::EmptyAlist, Ty::Alist(_, _))
            );
            if field.explicit_type
                && !field.ty.accepts(&inferred, self.symbols)
                && !empty_list_gains_elements
            {
                continue;
            }
            if field.ty != inferred {
                field.ty = inferred;
                changed = true;
            }
        }
        changed
    }

    fn prove_initializations(&mut self) {
        let field_keys: HashSet<(String, String)> = self.fields.keys().cloned().collect();
        let owners_with_descendants = self.symbols.declared_descendant_owners();
        let owners_with_effectful_initializers: HashSet<String> = self
            .fields
            .iter()
            .filter(|(_, field)| {
                !field.initially_null
                    && constructor_literal_type(&field.origin["initializer"]).is_none()
            })
            .map(|((owner, _), _)| owner.clone())
            .collect();
        for ((owner, name), field) in &mut self.fields {
            if (field.phase.is_some() && field.phase.as_deref() != Some("New"))
                || !field.initially_null
                || !self.symbols.is_subtype(owner, "/datum")
                || self.symbols.is_subtype(owner, "/atom")
                || owners_with_descendants.contains(owner)
                || self
                    .symbols
                    .duplicate_procs
                    .contains(&(owner.clone(), "New".into()))
                || owners_with_effectful_initializers.contains(owner)
            {
                continue;
            }
            let mut ancestor = self.symbols.parent(owner);
            let mut seen_ancestors = HashSet::new();
            let mut inherited_new = false;
            while let Some(current) = ancestor {
                if !seen_ancestors.insert(current.clone()) {
                    inherited_new = true;
                    break;
                }
                if self.procs.contains_key(&(current.clone(), "New".into())) {
                    inherited_new = true;
                    break;
                }
                ancestor = self.symbols.parent(&current);
            }
            if inherited_new {
                continue;
            }
            let Some(body) = self.new_bodies.get(owner) else {
                continue;
            };
            field.proved_initialization =
                constructor_paths(body, 1, owner, name, &field.ty, &field_keys, self.symbols)
                    .is_some_and(|paths| paths & 1 == 0);
        }
    }

    fn apply_overrides(&mut self) {
        for item in &self.overrides {
            let owner = item["owner"].as_str().unwrap_or("");
            let name = item["name"].as_str().unwrap_or("");
            let Some(key) = self.field_key(owner, name) else {
                continue;
            };
            let field_type = self.fields[&key].ty.clone();
            let value = if !field_type.has_unknown()
                && self.literal_collection_accepts(&field_type, &item["initializer"], owner)
            {
                field_type.nonnull()
            } else {
                self.expression(&item["initializer"], &HashMap::new(), owner)
            };
            let field = self.fields.get_mut(&key).expect("resolved field exists");
            if value.has_unknown()
                && !matches!(
                    (&value, field.ty.nonnull()),
                    (Ty::EmptyList, Ty::List(_) | Ty::Assoc(_, _))
                        | (Ty::EmptyAlist, Ty::Alist(_, _))
                )
            {
                field.saw_unknown_write = true;
            } else if field.evidence == Ty::Null {
                field.evidence = value;
            } else {
                let joined = field.evidence.join(&value, self.symbols);
                if joined == Ty::Unknown || matches!(joined, Ty::OneOf(_)) {
                    field.conflict = true;
                }
                field.evidence = joined;
            }
        }
    }

    fn check_overrides_values(&mut self) {
        for item in self.overrides.clone() {
            let owner = item["owner"].as_str().unwrap_or("");
            let name = item["name"].as_str().unwrap_or("");
            let Some(key) = self.field_key(owner, name) else {
                continue;
            };
            let field = self.fields[&key].clone();
            let value = self.expression(&item["initializer"], &HashMap::new(), owner);
            let selected =
                self.strict(&item) || self.selection.includes(source(&field.origin).0.as_str());
            // A fresh literal can be checked entry by entry against a wider
            // collection contract. Existing mutable collections remain invariant.
            if selected && self.literal_collection_accepts(&field.ty, &item["initializer"], owner) {
                self.coverage.checked_assignments += 1;
                continue;
            }
            self.assignment_with_policy(
                &item,
                &field.ty,
                &value,
                &format!("override {owner}.{name}"),
                selected,
            );
        }
    }

    fn check_field_initializers(&mut self) {
        let declarations: Vec<_> = self.fields.values().cloned().collect();
        for field in declarations {
            let initializer = &field.origin["initializer"];
            if initializer.is_null() || kind(initializer) == "DMASTConstantNull" {
                continue;
            }
            let owner = field.origin["owner"].as_str().unwrap_or("");
            let name = field.origin["name"].as_str().unwrap_or("");
            let selected = self.strict(&field.origin);
            if selected && self.literal_collection_accepts(&field.ty, initializer, owner) {
                self.coverage.checked_assignments += 1;
                continue;
            }
            let actual = self.expression(initializer, &HashMap::new(), owner);
            self.assignment_with_policy(
                &field.origin,
                &field.ty,
                &actual,
                &format!("initializer {owner}.{name}"),
                selected,
            );
        }
    }

    fn literal_collection_accepts(&self, expected: &Ty, literal: &Value, owner: &str) -> bool {
        if kind(literal) != "DMASTList" {
            return false;
        }
        let Some(entries) = f(literal, "Values").as_array() else {
            return false;
        };
        let is_alist = f(literal, "IsAList").as_bool() == Some(true);
        let expected = expected.nonnull();
        if let Ty::Record(fields) = &expected {
            if is_alist || expected.has_unknown() {
                return false;
            }
            let mut seen = HashSet::new();
            for entry in entries {
                if kind(entry) != "DMASTCallParameter" {
                    return false;
                }
                let key = f(entry, "Key");
                if kind(key) != "DMASTConstantString" {
                    return false;
                }
                let Some(name) = f(key, "Value").as_str() else {
                    return false;
                };
                let Some((value_type, _)) = fields.get(name) else {
                    return false;
                };
                if !seen.insert(name)
                    || !self.literal_value_accepts(value_type, f(entry, "Value"), owner)
                {
                    return false;
                }
            }
            return fields
                .iter()
                .all(|(name, (_, optional))| *optional || seen.contains(name.as_str()));
        }
        let (expected_key, expected_value) = match &expected {
            Ty::List(value) if !is_alist => (None, value.as_ref()),
            Ty::Assoc(key, value) if !is_alist => (Some(key.as_ref()), value.as_ref()),
            Ty::Alist(key, value) if is_alist => (Some(key.as_ref()), value.as_ref()),
            _ => return false,
        };
        if expected.has_unknown() || entries.is_empty() {
            return false;
        }
        entries.iter().all(|entry| {
            if kind(entry) != "DMASTCallParameter" {
                return false;
            }
            let key = f(entry, "Key");
            match expected_key {
                Some(ty) if !key.is_null() => {
                    let actual = self.expression(key, &HashMap::new(), owner);
                    if !ty.accepts(&actual, self.symbols) {
                        return false;
                    }
                }
                None if key.is_null() => {}
                _ => return false,
            }
            self.literal_value_accepts(expected_value, f(entry, "Value"), owner)
        })
    }

    fn literal_value_accepts(&self, expected: &Ty, value: &Value, owner: &str) -> bool {
        self.literal_collection_accepts(expected, value, owner)
            || expected.accepts(
                &self.expression(value, &HashMap::new(), owner),
                self.symbols,
            )
    }

    fn check_overrides(&mut self) {
        let names: Vec<_> = self.procs.keys().cloned().collect();
        for (owner, name) in names {
            let Some(child) = self.procs.get(&(owner.clone(), name.clone())).cloned() else {
                continue;
            };
            let Some(parent) = self.symbols.parent(&owner) else {
                continue;
            };
            let Some(base) = self.signature(&parent, &name).cloned() else {
                continue;
            };
            if !self.selection.includes(&child.path) && !self.selection.includes(&base.path) {
                continue;
            }
            let here = Finding {
                rule: "override-contract",
                path: child.path.clone(),
                line: child.line,
                severity: "error",
                message: String::new(),
            };
            if child.parameters.len() < base.parameters.len() {
                self.findings.push(Finding {
                    message: format!("{owner}/{name} removes parameters accepted by its parent"),
                    ..here.clone()
                });
            }
            for (index, expected) in base.parameters.iter().enumerate() {
                let Some(actual) = child.parameters.get(index) else {
                    break;
                };
                if actual.name != expected.name {
                    self.findings.push(Finding { message: format!("{owner}/{name} renames parent parameter {} to {}; named calls may break", expected.name, actual.name), ..here.clone() });
                }
                if actual.ty.has_unknown() || expected.ty.has_unknown() {
                    self.findings.push(Finding {
                        rule: "unknown-override-type",
                        message: format!(
                            "{owner}/{name} parameter {} cannot be checked against its parent",
                            expected.name
                        ),
                        ..here.clone()
                    });
                } else if !actual.ty.accepts(&expected.ty, self.symbols) {
                    self.findings.push(Finding {
                        message: format!(
                            "{owner}/{name} narrows accepted type of {} from {} to {}",
                            expected.name,
                            expected.ty.label(),
                            actual.ty.label()
                        ),
                        ..here.clone()
                    });
                }
            }
            if !self.generated_admin_verb_override(&owner, &name, &base) {
                for added in child.parameters.iter().skip(base.parameters.len()) {
                    if !added.has_default && !added.ty.may_be_null() {
                        self.findings.push(Finding {
                            message: format!(
                                "{owner}/{name} adds required parameter {}",
                                added.name
                            ),
                            ..here.clone()
                        });
                    }
                }
            }
            if base.result_required {
                if child.result.has_unknown() || base.result.has_unknown() {
                    self.findings.push(Finding {
                        rule: "unknown-override-result",
                        message: format!(
                            "{owner}/{name} return contract cannot be checked against its parent"
                        ),
                        ..here.clone()
                    });
                } else if !base.result.accepts(&child.result, self.symbols) {
                    self.findings.push(Finding {
                        message: format!(
                            "{owner}/{name} returns {} but parent promises {}",
                            child.result.label(),
                            base.result.label()
                        ),
                        ..here.clone()
                    });
                }
            }
        }
    }

    fn infer_parameters(&mut self) -> bool {
        // Call-site evidence is a useful storage-type hypothesis, but DM
        // procedures are open to dynamic calls. Keep that boundary visible in
        // strict diagnostics instead of claiming the parameter is proved.
        let mut changed = false;
        for ((owner, name, index), observed) in &self.param_evidence {
            let key = (owner.clone(), name.clone());
            let Some(versions) = self.proc_versions.get(&key) else {
                continue;
            };
            let Some(last) = versions
                .last()
                .and_then(|version| version.parameters.get(*index))
            else {
                continue;
            };
            // A call resolves to the effective (last) definition. Earlier DM
            // definitions may still run via `..()`. Only share an inferred
            // storage type when their positional parameters and defaults are
            // compatible with that effective definition.
            let aligned = versions.iter().all(|version| {
                version.parameters.get(*index).is_some_and(|parameter| {
                    parameter.name == last.name
                        && (parameter.ty == Ty::Unknown || parameter.ty == last.ty)
                })
            });
            if !aligned || observed.conflict {
                continue;
            }
            let mut candidate = if observed.calls > 0 && observed.ty != Ty::Null {
                observed.ty.nonnull()
            } else {
                Ty::Unknown
            };
            for version in versions {
                let param = &version.parameters[*index];
                if param.has_default {
                    if !param.default_ty.is_precise() || param.default_ty.may_be_null() {
                        candidate = Ty::Unknown;
                        break;
                    }
                    candidate = if candidate == Ty::Unknown {
                        param.default_ty.clone()
                    } else {
                        candidate.join(&param.default_ty, self.symbols)
                    };
                }
            }
            if let Some(required) = &observed.constraint {
                candidate = if candidate == Ty::Unknown {
                    required.clone()
                } else if required.accepts(&candidate, self.symbols) {
                    candidate
                } else {
                    Ty::Unknown
                };
            }
            if !candidate.is_precise()
                || candidate.may_be_null()
                || matches!(candidate, Ty::OneOf(_))
            {
                continue;
            }
            let Some(versions) = self.proc_versions.get_mut(&key) else {
                continue;
            };
            for version in versions.iter_mut() {
                let param = &mut version.parameters[*index];
                if param.ty == Ty::Unknown {
                    param.ty = candidate.clone();
                    param.inferred_from_calls = true;
                    changed = true;
                }
            }
            if let Some(last) = versions.last() {
                self.procs.insert(key, last.clone());
            }
        }
        changed
    }

    fn infer_returns(&mut self) {
        let candidates: Vec<_> = self.return_bodies.keys().cloned().collect();
        let mut definitions_by_name: HashMap<String, Vec<(String, String)>> = HashMap::new();
        for key in self.procs.keys() {
            definitions_by_name
                .entry(key.1.clone())
                .or_default()
                .push(key.clone());
        }
        // Allow one final no-change round after the longest acyclic chain.
        let limit = candidates.len().saturating_add(1).clamp(1, 33);
        let mut changed = false;
        let mut deferred_dispatch = Vec::new();
        for _ in 0..limit {
            changed = false;
            for (owner, name) in &candidates {
                let key = (owner.clone(), name.clone());
                let Some(bodies) = self.return_bodies.get(&key) else {
                    continue;
                };
                for (version, body) in bodies {
                    let Some(sig) = self
                        .proc_versions
                        .get(&key)
                        .and_then(|versions| versions.get(*version))
                        .cloned()
                    else {
                        continue;
                    };
                    if sig.result_required || sig.result != Ty::Unknown {
                        continue;
                    }
                    self.current_proc = Some(name.clone());
                    self.current_proc_version = Some(*version);
                    let inferred = if !has_explicit_value_return(body)
                        && !has_implicit_result_assignment(body)
                    {
                        Ty::Void
                    } else if let Some(proved) = self.prove_record_builder(body, &sig) {
                        proved
                    } else {
                        let mut vars: HashMap<String, Ty> = sig
                            .parameters
                            .iter()
                            .map(|param| {
                                (param.name.clone(), with_nullable(param.ty.clone(), true))
                            })
                            .collect();
                        vars.insert("src".into(), Ty::Path(owner.clone()));
                        let mut result_slot = Ty::Null;
                        let mut fresh_result = false;
                        let mut fresh_locals = HashSet::new();
                        let (returned, continues) = self.summarize_block(
                            body,
                            owner,
                            name,
                            &mut vars,
                            &mut result_slot,
                            &mut fresh_result,
                            &mut fresh_locals,
                        );
                        let result = if continues {
                            join_return(returned, Some(result_slot), self.symbols)
                        } else {
                            returned
                        };
                        match result {
                            Some(Ty::Null) if !has_explicit_value_return(body) => Ty::Void,
                            Some(ty) if ty.is_precise() => ty,
                            _ => continue,
                        }
                    };
                    let final_version = self
                        .proc_versions
                        .get(&key)
                        .is_some_and(|versions| *version + 1 == versions.len());
                    let dispatch_result = final_version
                        .then(|| {
                            self.virtual_return_result(owner, name, &inferred, &definitions_by_name)
                        })
                        .flatten();
                    if let Some(signature) = self
                        .proc_versions
                        .get_mut(&key)
                        .and_then(|versions| versions.get_mut(*version))
                    {
                        signature.result = inferred.clone();
                        signature.result_required = true;
                        signature.inferred_nullable_result =
                            inferred.may_be_null() && !nullable(self.contracts, owner, name, None);
                    }
                    if let Some(dispatch_result) = dispatch_result {
                        if let Some(signature) = self.procs.get_mut(&key) {
                            signature.result = dispatch_result;
                            signature.result_required = true;
                            signature.inferred_nullable_result = signature.result.may_be_null()
                                && !nullable(self.contracts, owner, name, None);
                        }
                    } else if final_version {
                        // A descendant may simply not have been inferred yet.
                        // Recheck the virtual signature after later bodies get
                        // their own results instead of freezing it as unknown.
                        deferred_dispatch.push(key.clone());
                    }
                    changed = true;
                }
            }
            // Check the descendant contract after a wave of body inference
            // settles, rather than rescanning common override families on
            // every intermediate round.
            if !changed {
                let mut still_deferred = Vec::new();
                for key in deferred_dispatch.drain(..) {
                    let Some(result) = self
                        .proc_versions
                        .get(&key)
                        .and_then(|versions| versions.last())
                        .map(|signature| signature.result.clone())
                    else {
                        continue;
                    };
                    if let Some(dispatch_result) = result
                        .is_precise()
                        .then(|| {
                            self.virtual_return_result(
                                &key.0,
                                &key.1,
                                &result,
                                &definitions_by_name,
                            )
                        })
                        .flatten()
                    {
                        if let Some(signature) = self.procs.get_mut(&key) {
                            signature.result = dispatch_result;
                            signature.result_required = true;
                            signature.inferred_nullable_result = signature.result.may_be_null()
                                && !nullable(self.contracts, &key.0, &key.1, None);
                            changed = true;
                        }
                    } else {
                        still_deferred.push(key);
                    }
                }
                deferred_dispatch = still_deferred;
            }
            if !changed {
                break;
            }
        }
        self.current_proc = None;
        self.current_proc_version = None;
        if changed {
            self.findings.push(Finding {
                rule: "return-inference-limit",
                path: "<ast>".into(),
                line: 1,
                severity: "error",
                message: "return inference did not reach a fixed point within 32 rounds".into(),
            });
        }
    }

    fn virtual_return_result(
        &self,
        owner: &str,
        name: &str,
        candidate: &Ty,
        definitions_by_name: &HashMap<String, Vec<(String, String)>>,
    ) -> Option<Ty> {
        let mut result: Option<Ty> = None;
        let mut has_void = false;
        let mut family = vec![candidate];
        for key in definitions_by_name.get(name).into_iter().flatten() {
            if key.0 != owner && self.symbols.is_subtype(&key.0, owner) {
                family.push(&self.proc_versions.get(key)?.last()?.result);
            }
        }
        for ty in family {
            if !ty.is_precise() {
                return None;
            }
            if *ty == Ty::Void {
                has_void = true;
            } else {
                result = Some(match result {
                    Some(previous) => previous.join(ty, self.symbols),
                    None => ty.clone(),
                });
            }
        }
        let result = match result {
            Some(result) if has_void => result.join(&Ty::Null, self.symbols),
            Some(result) => result,
            None => Ty::Void,
        };
        result.is_precise().then_some(result)
    }

    fn prove_record_builder(&self, body: &Value, sig: &Signature) -> Option<Ty> {
        let statements = simple_statements(body)?;
        let [base, conditional] = statements.as_slice() else {
            return None;
        };
        if kind(base) != "DMASTProcStatementExpression" {
            return None;
        }
        let assignment = f(base, "Expression");
        if kind(assignment) != "DMASTAssign" || kind(f(assignment, "LHS")) != "DMASTCallableSelf" {
            return None;
        }
        let literal = f(assignment, "RHS");
        if kind(literal) != "DMASTList" || f(literal, "IsAList").as_bool() == Some(true) {
            return None;
        }
        let mut fields = BTreeMap::new();
        for entry in f(literal, "Values").as_array()? {
            if kind(entry) != "DMASTCallParameter" || kind(f(entry, "Key")) != "DMASTConstantString"
            {
                return None;
            }
            let name = f(f(entry, "Key"), "Value").as_str()?;
            let value = f(entry, "Value");
            if kind(value) != "DMASTIdentifier" {
                return None;
            }
            let source = f(value, "Identifier").as_str()?;
            let ty = with_nullable(
                sig.parameters
                    .iter()
                    .find(|param| param.name == source)?
                    .ty
                    .clone(),
                true,
            );
            if !ty.is_precise() || fields.insert(name.into(), (ty, false)).is_some() {
                return None;
            }
        }
        if fields.is_empty()
            || kind(conditional) != "DMASTProcStatementIf"
            || !f(conditional, "ElseBody").is_null()
        {
            return None;
        }
        let condition = f(conditional, "Condition");
        if kind(condition) != "DMASTIdentifier" {
            return None;
        }
        let extra_name = f(condition, "Identifier").as_str()?;
        let extra = sig
            .parameters
            .iter()
            .find(|param| param.name == extra_name)?;
        let Ty::Record(extra_fields) = extra.ty.nonnull() else {
            return None;
        };
        if extra_fields.values().any(|(_, optional)| !optional)
            || extra_fields.keys().any(|name| fields.contains_key(name))
        {
            return None;
        }
        let conditional_body = simple_statements(f(conditional, "Body"))?;
        let [loop_statement] = conditional_body.as_slice() else {
            return None;
        };
        if kind(loop_statement) != "DMASTProcStatementFor"
            || !f(loop_statement, "Expression2").is_null()
            || !f(loop_statement, "Expression3").is_null()
            || !f(loop_statement, "DMTypes").is_null()
        {
            return None;
        }
        let iterator = f(loop_statement, "Expression1");
        if kind(iterator) != "DMASTExpressionIn" || !identifier_is(f(iterator, "RHS"), extra_name) {
            return None;
        }
        let declaration = f(iterator, "LHS");
        if kind(declaration) != "DMASTVarDeclExpression" {
            return None;
        }
        let key_name = f(f(declaration, "DeclPath"), "Path")
            .as_str()?
            .strip_prefix("var/")?;
        if key_name.is_empty() || key_name.contains('/') {
            return None;
        }
        let loop_body = simple_statements(f(loop_statement, "Body"))?;
        let [copy] = loop_body.as_slice() else {
            return None;
        };
        if kind(copy) != "DMASTProcStatementExpression" {
            return None;
        }
        let copy = f(copy, "Expression");
        if kind(copy) != "DMASTAssign"
            || !record_index_is(f(copy, "LHS"), "", key_name)
            || !record_index_is(f(copy, "RHS"), extra_name, key_name)
        {
            return None;
        }
        for (name, value) in extra_fields {
            fields.insert(name, value);
        }
        let result = Ty::Record(fields);
        result.is_precise().then_some(result)
    }

    fn fresh_result_index_type(
        &self,
        lhs: &Value,
        current: &Ty,
        value: &Ty,
        vars: &HashMap<String, Ty>,
        owner: &str,
    ) -> Ty {
        let Some([operation]) = f(lhs, "Operations").as_array().map(Vec::as_slice) else {
            return Ty::Unknown;
        };
        if kind(operation) != "IndexOperation" {
            return Ty::Unknown;
        }
        let index = f(operation, "Index");
        let key = self.expression(index, vars, owner);
        match (current, key) {
            (Ty::EmptyList, Ty::Text) => {
                if kind(index) == "DMASTConstantString" {
                    let Some(name) = f(index, "Value").as_str() else {
                        return Ty::Unknown;
                    };
                    Ty::Record(BTreeMap::from([(
                        name.into(),
                        (value.clone(), value.may_be_null()),
                    )]))
                } else if value.is_precise() && !value.may_be_null() {
                    Ty::Assoc(Box::new(Ty::Text), Box::new(value.clone()))
                } else {
                    Ty::Unknown
                }
            }
            (Ty::EmptyList, Ty::Num) if value.is_precise() && !value.may_be_null() => {
                Ty::List(Box::new(value.clone()))
            }
            (Ty::Record(fields), Ty::Text) if kind(index) == "DMASTConstantString" => {
                let Some(name) = f(index, "Value").as_str() else {
                    return Ty::Unknown;
                };
                let mut fields = fields.clone();
                fields.insert(name.into(), (value.clone(), value.may_be_null()));
                Ty::Record(fields)
            }
            (Ty::Assoc(existing_key, existing_value), Ty::Text)
                if **existing_key == Ty::Text && value.is_precise() && !value.may_be_null() =>
            {
                Ty::Assoc(
                    existing_key.clone(),
                    Box::new(existing_value.join(value, self.symbols)),
                )
            }
            (Ty::List(existing), Ty::Num) if value.is_precise() && !value.may_be_null() => {
                Ty::List(Box::new(existing.join(value, self.symbols)))
            }
            _ => Ty::Unknown,
        }
    }

    #[allow(clippy::too_many_arguments)] // Recursive analysis threads the procedure identity and mutable flow state.
    fn summarize_block(
        &self,
        block: &Value,
        owner: &str,
        name: &str,
        vars: &mut HashMap<String, Ty>,
        result_slot: &mut Ty,
        fresh_result: &mut bool,
        fresh_locals: &mut HashSet<String>,
    ) -> (Option<Ty>, bool) {
        let Some(statements) = f(block, "Statements").as_array() else {
            return (None, true);
        };
        let mut returned = None;
        for statement in statements {
            match kind(statement) {
                "DMASTProcStatementReturn" => {
                    let value = f(statement, "Value");
                    let ty = if value.is_null() || kind(value) == "DMASTCallableSelf" {
                        result_slot.clone()
                    } else if kind(value) == "DMASTProcCall"
                        && kind(f(value, "Callable")) == "DMASTCallableSuper"
                    {
                        self.parent_signature(owner, name)
                            .map(|sig| sig.result.clone())
                            .unwrap_or(Ty::Unknown)
                    } else {
                        self.expression(value, vars, owner)
                    };
                    return (join_return(returned, Some(ty), self.symbols), false);
                }
                "DMASTProcStatementVarDeclaration" => {
                    let local = f(statement, "Name").as_str().unwrap_or("");
                    let initial = f(statement, "Value");
                    let escaped: Vec<_> = fresh_locals
                        .iter()
                        .filter(|name| mentions_identifier(initial, name))
                        .cloned()
                        .collect();
                    for name in escaped {
                        fresh_locals.remove(&name);
                        vars.insert(name, Ty::Unknown);
                    }
                    let native = declared(f(statement, "Type"), f(statement, "ValueType"));
                    let literal_record = self.literal_record_fact(initial, vars, owner);
                    let inferred = if initial.is_null() {
                        if f(statement, "IsGlobal").as_bool() == Some(true) && native != Ty::Unknown
                        {
                            with_nullable(native.clone(), true)
                        } else {
                            Ty::Null
                        }
                    } else {
                        literal_record
                            .clone()
                            .unwrap_or_else(|| self.expression(initial, vars, owner))
                    };
                    let inferred =
                        if kind(initial) == "DMASTNewInferred" && matches!(native, Ty::Path(_)) {
                            native
                        } else {
                            inferred
                        };
                    let fresh = empty_list_literal(initial) || literal_record.is_some();
                    vars.insert(local.into(), inferred);
                    if fresh {
                        fresh_locals.insert(local.into());
                    } else {
                        fresh_locals.remove(local);
                    }
                    if references_implicit_result(initial) {
                        *fresh_result = false;
                        *result_slot = Ty::Unknown;
                    }
                }
                "DMASTProcStatementExpression" => {
                    let expr = f(statement, "Expression");
                    if kind(expr) == "DMASTAssign" {
                        let lhs = f(expr, "LHS");
                        let rhs = f(expr, "RHS");
                        let escaped: Vec<_> = fresh_locals
                            .iter()
                            .filter(|name| mentions_identifier(rhs, name))
                            .cloned()
                            .collect();
                        for name in escaped {
                            fresh_locals.remove(&name);
                            vars.insert(name, Ty::Unknown);
                        }
                        let ty = if kind(rhs) == "DMASTProcCall"
                            && kind(f(rhs, "Callable")) == "DMASTCallableSuper"
                        {
                            self.parent_signature(owner, name)
                                .map(|sig| sig.result.clone())
                                .unwrap_or(Ty::Unknown)
                        } else {
                            self.expression(rhs, vars, owner)
                        };
                        if kind(lhs) == "DMASTCallableSelf" {
                            *result_slot = ty;
                            *fresh_result = empty_list_literal(rhs);
                        } else if kind(lhs) == "DMASTDereference"
                            && kind(f(lhs, "Expression")) == "DMASTCallableSelf"
                        {
                            *result_slot = if *fresh_result && !contains_unknown_effect(rhs) {
                                self.fresh_result_index_type(lhs, result_slot, &ty, vars, owner)
                            } else {
                                Ty::Unknown
                            };
                            *fresh_result &= result_slot.is_precise()
                                || matches!(result_slot, Ty::EmptyList | Ty::Record(_));
                        } else if kind(lhs) == "DMASTIdentifier" {
                            if let Some(local) = f(lhs, "Identifier").as_str() {
                                let literal_record = self.literal_record_fact(rhs, vars, owner);
                                let fresh = empty_list_literal(rhs) || literal_record.is_some();
                                let ty = literal_record.unwrap_or(ty);
                                vars.insert(local.into(), ty);
                                if fresh {
                                    fresh_locals.insert(local.into());
                                } else {
                                    fresh_locals.remove(local);
                                }
                            }
                        } else if kind(lhs) == "DMASTDereference" {
                            if let Some(local) = place(f(lhs, "Expression"))
                                .filter(|name| fresh_locals.contains(name))
                            {
                                let current = vars.get(&local).cloned().unwrap_or(Ty::Unknown);
                                let next =
                                    self.fresh_result_index_type(lhs, &current, &ty, vars, owner);
                                vars.insert(local.clone(), next.clone());
                                if next == Ty::Unknown {
                                    fresh_locals.remove(&local);
                                }
                            }
                        }
                        if references_implicit_result(rhs) && kind(lhs) != "DMASTCallableSelf" {
                            *fresh_result = false;
                            *result_slot = Ty::Unknown;
                        }
                    }
                    if contains_unknown_effect(expr) {
                        invalidate_after_preserving_fresh(expr, vars, fresh_locals);
                        if *fresh_result {
                            *result_slot = Ty::Unknown;
                            *fresh_result = false;
                        }
                        if matches!(
                            result_slot,
                            Ty::Path(_) | Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _)
                        ) {
                            *result_slot = Ty::Nullable(Box::new(result_slot.clone()));
                        }
                    }
                }
                "DMASTProcStatementIf" => {
                    let condition = f(statement, "Condition");
                    if contains_unknown_effect(condition) {
                        invalidate_after_preserving_fresh(condition, vars, fresh_locals);
                        if *fresh_result {
                            *result_slot = Ty::Unknown;
                            *fresh_result = false;
                        }
                        if matches!(
                            result_slot,
                            Ty::Path(_) | Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _)
                        ) {
                            *result_slot = Ty::Nullable(Box::new(result_slot.clone()));
                        }
                    }
                    let mut yes_vars = vars.clone();
                    let mut no_vars = vars.clone();
                    narrow(condition, true, &mut yes_vars);
                    narrow(condition, false, &mut no_vars);
                    let mut yes_slot = result_slot.clone();
                    let mut no_slot = result_slot.clone();
                    let mut yes_fresh = *fresh_result;
                    let mut no_fresh = *fresh_result;
                    let mut yes_locals = fresh_locals.clone();
                    let mut no_locals = fresh_locals.clone();
                    let (yes_return, yes_continues) = self.summarize_block(
                        f(statement, "Body"),
                        owner,
                        name,
                        &mut yes_vars,
                        &mut yes_slot,
                        &mut yes_fresh,
                        &mut yes_locals,
                    );
                    let (no_return, no_continues) = if f(statement, "ElseBody").is_null() {
                        (None, true)
                    } else {
                        self.summarize_block(
                            f(statement, "ElseBody"),
                            owner,
                            name,
                            &mut no_vars,
                            &mut no_slot,
                            &mut no_fresh,
                            &mut no_locals,
                        )
                    };
                    returned = join_return(returned, yes_return, self.symbols);
                    returned = join_return(returned, no_return, self.symbols);
                    match (yes_continues, no_continues) {
                        (true, true) => {
                            *vars = join_env(&yes_vars, &no_vars, self.symbols);
                            *result_slot = yes_slot.join(&no_slot, self.symbols);
                            *fresh_result = yes_fresh && no_fresh;
                            *fresh_locals = yes_locals.intersection(&no_locals).cloned().collect();
                        }
                        (true, false) => {
                            *vars = yes_vars;
                            *result_slot = yes_slot;
                            *fresh_result = yes_fresh;
                            *fresh_locals = yes_locals;
                        }
                        (false, true) => {
                            *vars = no_vars;
                            *result_slot = no_slot;
                            *fresh_result = no_fresh;
                            *fresh_locals = no_locals;
                        }
                        (false, false) => return (returned, false),
                    }
                }
                "DMASTProcStatementSwitch" => {
                    let Some(cases) = f(statement, "Cases").as_array().filter(|cases| {
                        cases.iter().all(|case| {
                            matches!(kind(case), "SwitchCaseValues" | "SwitchCaseDefault")
                        })
                    }) else {
                        returned = join_return(returned, Some(Ty::Unknown), self.symbols);
                        vars.values_mut().for_each(|ty| *ty = Ty::Unknown);
                        *result_slot = Ty::Unknown;
                        *fresh_result = false;
                        continue;
                    };
                    let value = f(statement, "Value");
                    if contains_unknown_effect(value) {
                        invalidate_after_preserving_fresh(value, vars, fresh_locals);
                        *result_slot = result_slot.join(&Ty::Null, self.symbols);
                        *fresh_result = false;
                    }
                    for case in cases {
                        for choice in f(case, "Values").as_array().into_iter().flatten() {
                            if contains_unknown_effect(choice) {
                                invalidate_after_preserving_fresh(choice, vars, fresh_locals);
                                *result_slot = result_slot.join(&Ty::Null, self.symbols);
                                *fresh_result = false;
                            }
                        }
                    }
                    let mut continuing = Vec::new();
                    let mut has_default = false;
                    for case in cases {
                        has_default |= kind(case) == "SwitchCaseDefault";
                        let mut arm_vars = vars.clone();
                        let mut arm_slot = result_slot.clone();
                        let mut arm_fresh = *fresh_result;
                        let mut arm_locals = fresh_locals.clone();
                        let (arm_return, arm_continues) = self.summarize_block(
                            f(case, "Body"),
                            owner,
                            name,
                            &mut arm_vars,
                            &mut arm_slot,
                            &mut arm_fresh,
                            &mut arm_locals,
                        );
                        returned = join_return(returned, arm_return, self.symbols);
                        if arm_continues {
                            continuing.push((arm_vars, arm_slot, arm_fresh, arm_locals));
                        }
                    }
                    if !has_default {
                        continuing.push((
                            vars.clone(),
                            result_slot.clone(),
                            *fresh_result,
                            fresh_locals.clone(),
                        ));
                    }
                    if continuing.is_empty() {
                        return (returned, false);
                    }
                    let (mut merged_vars, mut merged_slot, mut merged_fresh, mut merged_locals) =
                        continuing.remove(0);
                    for (arm_vars, arm_slot, arm_fresh, arm_locals) in continuing {
                        merged_vars = join_env(&merged_vars, &arm_vars, self.symbols);
                        merged_slot = merged_slot.join(&arm_slot, self.symbols);
                        merged_fresh &= arm_fresh;
                        merged_locals = merged_locals.intersection(&arm_locals).cloned().collect();
                    }
                    *vars = merged_vars;
                    *result_slot = merged_slot;
                    *fresh_result = merged_fresh;
                    *fresh_locals = merged_locals;
                }
                "DMASTProcStatementFor"
                | "DMASTProcStatementWhile"
                | "DMASTProcStatementDoWhile" => {
                    for header in ["Expression1", "Expression2", "Expression3", "Conditional"] {
                        let expression = f(statement, header);
                        if contains_unknown_effect(expression) {
                            invalidate_after_preserving_fresh(expression, vars, fresh_locals);
                            *fresh_result = false;
                        }
                    }
                    let mut body_vars = vars.clone();
                    let iterator = f(statement, "Expression1");
                    if kind(iterator) == "DMASTExpressionIn" {
                        if let Some((local, declared)) = iterator_declaration(f(iterator, "LHS")) {
                            let collection = self.expression(f(iterator, "RHS"), vars, owner);
                            let element = match collection {
                                Ty::List(value) => *value,
                                Ty::Assoc(key, _) | Ty::Alist(key, _) => *key,
                                _ => Ty::Unknown,
                            };
                            body_vars.insert(
                                local,
                                if declared.is_precise() {
                                    declared
                                } else {
                                    element
                                },
                            );
                        }
                    }
                    let mut body_slot = result_slot.clone();
                    let mut body_fresh = *fresh_result;
                    let mut body_locals = fresh_locals.clone();
                    let (body_return, _) = self.summarize_block(
                        f(statement, "Body"),
                        owner,
                        name,
                        &mut body_vars,
                        &mut body_slot,
                        &mut body_fresh,
                        &mut body_locals,
                    );
                    returned = join_return(returned, body_return, self.symbols);
                    *vars = join_env(vars, &body_vars, self.symbols);
                    *result_slot = result_slot.join(&body_slot, self.symbols);
                    *fresh_result &= body_fresh;
                    *fresh_locals = fresh_locals.intersection(&body_locals).cloned().collect();
                }
                "DMASTProcStatementSpawn" => {
                    if references_implicit_result(f(statement, "Body")) {
                        *result_slot = Ty::Unknown;
                        *fresh_result = false;
                    }
                }
                // These end the current loop arm without returning from the proc.
                // The loop itself may still fall through to following statements.
                "DMASTProcStatementBreak" | "DMASTProcStatementContinue" => {
                    return (returned, false);
                }
                other if other.starts_with("DMASTProcStatement") => {
                    returned = join_return(returned, Some(Ty::Unknown), self.symbols);
                }
                _ => {}
            }
        }
        (returned, true)
    }

    fn assignment(&mut self, node: &Value, expected: &Ty, actual: &Ty, subject: &str) {
        self.assignment_with_policy(node, expected, actual, subject, self.strict(node));
    }

    fn assignment_with_policy(
        &mut self,
        node: &Value,
        expected: &Ty,
        actual: &Ty,
        subject: &str,
        enforce: bool,
    ) {
        if !enforce {
            return;
        }
        let compatible_empty = match actual {
            Ty::EmptyList => matches!(
                expected.nonnull(),
                Ty::List(_) | Ty::Assoc(_, _) | Ty::Record(_)
            ),
            Ty::EmptyAlist => matches!(expected.nonnull(), Ty::Alist(_, _)),
            _ => false,
        };
        if compatible_empty && expected.accepts(actual, self.symbols) {
            self.coverage.checked_assignments += 1;
            return;
        }
        if matches!(actual, Ty::EmptyList | Ty::EmptyAlist)
            && !expected.has_unknown()
            && expected.nonnull() != *actual
        {
            self.coverage.checked_assignments += 1;
            self.findings.push(issue(
                node,
                "strict-type-assignment",
                format!(
                    "{subject}: {} cannot be assigned to {}",
                    actual.label(),
                    expected.label()
                ),
            ));
            return;
        }
        if actual.has_unknown() || expected.has_unknown() {
            self.coverage.unresolved_assignments += 1;
            let next_step = match (actual.has_unknown(), expected.has_unknown()) {
                (true, true) => {
                    self.coverage.unresolved_both_types += 1;
                    "source and destination types need proof"
                }
                (true, false) => {
                    self.coverage.unresolved_source_types += 1;
                    "source type needs proof"
                }
                (false, true) => {
                    self.coverage.unresolved_destination_types += 1;
                    "destination type needs a contract"
                }
                (false, false) => unreachable!(),
            };
            self.findings.push(issue(
                node,
                "unknown-type-flow",
                format!(
                    "{subject}: cannot prove {} fits {}; {next_step}",
                    actual.label(),
                    expected.label()
                ),
            ));
        } else {
            self.coverage.checked_assignments += 1;
            if !expected.accepts(actual, self.symbols) {
                self.findings.push(issue(
                    node,
                    "strict-type-assignment",
                    format!(
                        "{subject}: {} cannot be assigned to {}",
                        actual.label(),
                        expected.label()
                    ),
                ));
            }
        }
    }

    fn unresolved_cause(&self, expr: &Value, owner: &str, env: &Env) -> &'static str {
        match kind(expr) {
            "DMASTIdentifier" => {
                let name = f(expr, "Identifier").as_str().unwrap_or("");
                if env.slots.contains_key(name) {
                    "Local or parameter type"
                } else if name == "args" {
                    "Dynamic arguments"
                } else if self.field_key(owner, name).is_some() {
                    "Field type"
                } else {
                    "Unresolved name"
                }
            }
            "DMASTDereference" => {
                let receiver = self.expression(f(expr, "Expression"), &env.facts, owner);
                if !receiver.is_precise() {
                    return "Receiver type";
                }
                if let Some(operation) = f(expr, "Operations")
                    .as_array()
                    .and_then(|operations| operations.last())
                {
                    return match kind(operation) {
                        "IndexOperation" => "Collection value",
                        "FieldOperation" => "Member field",
                        "CallOperation" => "Member return",
                        _ => "Dereference result",
                    };
                }
                "Dereference result"
            }
            "DMASTProcCall" => "Direct call return",
            "DMASTCall" => "Dynamic call target",
            "DMASTList" | "DMASTNewList" => {
                let items = if kind(expr) == "DMASTList" {
                    f(expr, "Values")
                } else {
                    f(expr, "Parameters")
                };
                if items.as_array().is_some_and(Vec::is_empty) {
                    "Empty collection literal"
                } else {
                    "Collection contents"
                }
            }
            "DMASTNewPath"
                if matches!(
                    f(f(f(expr, "Path"), "Value"), "Path").as_str(),
                    Some("/list" | "/alist")
                ) =>
            {
                "Collection constructor contents"
            }
            "DMASTNegate" | "DMASTBinaryNot" | "DMASTPreIncrement" | "DMASTPostIncrement"
            | "DMASTPreDecrement" | "DMASTPostDecrement" => "Numeric operand type",
            "DMASTTernary" => "Conditional branch types",
            "DMASTExpressionWrapped" => "Wrapped value",
            _ => "Operator or unsupported expression",
        }
    }

    fn unknown_root(&self, expr: &Value, owner: &str, env: &Env, depth: usize) -> UnknownRootCount {
        let make = |category: &str, symbol: String, node: &Value| {
            let (path, line) = source(node);
            UnknownRootCount {
                category: category.into(),
                symbol,
                path,
                line,
                count: 1,
            }
        };
        if depth >= 32 {
            return make("Unresolved expression", kind(expr).into(), expr);
        }
        match kind(expr) {
            "DMASTExpressionWrapped" => {
                return self.unknown_root(f(expr, "Value"), owner, env, depth + 1);
            }
            "DMASTIdentifier" => {
                let name = f(expr, "Identifier").as_str().unwrap_or("");
                if name == "args" && !env.slots.contains_key(name) {
                    return make("Dynamic arguments", format!("{owner}:args"), expr);
                }
                if let Some(storage) = env.slots.get(name) {
                    if let Some((path, line)) =
                        env.origins.get(&format!("{FLOW_ORIGIN_PREFIX}{name}"))
                    {
                        let distinct_from_declaration =
                            env.origins.get(name).is_none_or(|(decl_path, decl_line)| {
                                decl_path != path || decl_line != line
                            });
                        if distinct_from_declaration {
                            return UnknownRootCount {
                                category: "Unverified value write".into(),
                                symbol: format!("{owner}/{name}"),
                                path: path.clone(),
                                line: *line,
                                count: 1,
                            };
                        }
                    }
                    if storage.is_precise() {
                        if let Some((path, line)) =
                            env.origins.get(&format!("{FLOW_ORIGIN_PREFIX}{name}"))
                        {
                            return UnknownRootCount {
                                category: "Unverified value write".into(),
                                symbol: format!("{owner}/{name}"),
                                path: path.clone(),
                                line: *line,
                                count: 1,
                            };
                        }
                        if let Some((path, line)) = env.origins.get(name) {
                            return UnknownRootCount {
                                category: "Local flow value".into(),
                                symbol: format!("{owner}/{name}"),
                                path: path.clone(),
                                line: *line,
                                count: 1,
                            };
                        }
                        return make("Flow fact", format!("{owner}/{name}"), expr);
                    }
                    if let Some(proc_name) = self.current_proc.as_deref() {
                        if let Some(signature) = self.procs.get(&(owner.into(), proc_name.into())) {
                            let category = if signature.parameters.iter().any(|p| p.name == name) {
                                "Parameter"
                            } else {
                                "Local"
                            };
                            let (path, line) = env
                                .origins
                                .get(name)
                                .cloned()
                                .unwrap_or_else(|| (signature.path.clone(), signature.line));
                            return UnknownRootCount {
                                category: category.into(),
                                symbol: format!("{owner}/{proc_name}:{name}"),
                                path,
                                line,
                                count: 1,
                            };
                        }
                    }
                    return make("Local", format!("{owner}:{name}"), expr);
                }
                if let Some(key) = self.field_key(owner, name) {
                    if let Some(field) = self.fields.get(&key) {
                        if field.ty.is_precise() {
                            if let Some((path, line)) =
                                env.origins.get(&format!("{FLOW_ORIGIN_PREFIX}{name}"))
                            {
                                return UnknownRootCount {
                                    category: "Unverified value write".into(),
                                    symbol: format!("{}.{}", key.0, key.1),
                                    path: path.clone(),
                                    line: *line,
                                    count: 1,
                                };
                            }
                            if let Some((path, line)) = env.origins.get(STALE_REFERENCES) {
                                return UnknownRootCount {
                                    category: "Unknown side effect".into(),
                                    symbol: format!("{}.{}", key.0, key.1),
                                    path: path.clone(),
                                    line: *line,
                                    count: 1,
                                };
                            }
                            return make("Flow fact", format!("{}.{}", key.0, key.1), expr);
                        }
                        return make("Field", format!("{}.{}", key.0, key.1), &field.origin);
                    }
                }
                return make("Unresolved name", format!("{owner}:{name}"), expr);
            }
            "DMASTProcCall" => {
                let name = f(f(expr, "Callable"), "Identifier").as_str().unwrap_or("");
                if let Some(key) = self.signature_key(owner, name) {
                    if let Some(signature) = self.procs.get(&key) {
                        if !signature.result.is_precise() {
                            return UnknownRootCount {
                                category: "Procedure return".into(),
                                symbol: format!("{}/{}", key.0, key.1),
                                path: signature.path.clone(),
                                line: signature.line,
                                count: 1,
                            };
                        }
                    }
                } else {
                    return make("Unresolved call", format!("{owner}/{name}"), expr);
                }
            }
            "DMASTDereference" => {
                let base = f(expr, "Expression");
                let mut receiver = self.expression(base, &env.facts, owner);
                if !receiver.is_precise() {
                    return self.unknown_root(base, owner, env, depth + 1);
                }
                if let Some(operations) = f(expr, "Operations").as_array() {
                    if operations.len() > 1 {
                        let prefix = serde_json::json!({
                            "kind": "DMASTDereference",
                            "file": expr["file"],
                            "line": expr["line"],
                            "fields": {
                                "Expression": base,
                                "Operations": &operations[..operations.len() - 1],
                            },
                        });
                        let prefix_type = self.expression(&prefix, &env.facts, owner);
                        if !prefix_type.is_precise() {
                            return self.unknown_root(&prefix, owner, env, depth + 1);
                        }
                        receiver = prefix_type;
                    }
                }
                if let Some(operation) = f(expr, "Operations").as_array().and_then(|ops| ops.last())
                {
                    let member = f(operation, "Identifier").as_str().unwrap_or("");
                    if let Ty::Path(path) = receiver.nonnull() {
                        if kind(operation) == "FieldOperation" {
                            if let Some(key) = self.field_key(&path, member) {
                                if let Some(field) = self.fields.get(&key) {
                                    if !field.ty.is_precise() {
                                        return make(
                                            "Field",
                                            format!("{}.{}", key.0, key.1),
                                            &field.origin,
                                        );
                                    }
                                }
                            } else {
                                return make("Member field", format!("{path}.{member}"), expr);
                            }
                        }
                        if kind(operation) == "CallOperation" {
                            if let Some(key) = self.signature_key(&path, member) {
                                if let Some(signature) = self.procs.get(&key) {
                                    if !signature.result.is_precise() {
                                        return UnknownRootCount {
                                            category: "Procedure return".into(),
                                            symbol: format!("{}/{}", key.0, key.1),
                                            path: signature.path.clone(),
                                            line: signature.line,
                                            count: 1,
                                        };
                                    }
                                }
                            } else {
                                return make("Member return", format!("{path}/{member}"), expr);
                            }
                        }
                    }
                    if kind(operation) == "IndexOperation" {
                        let index = f(operation, "Index");
                        if !self.expression(index, &env.facts, owner).is_precise() {
                            return self.unknown_root(index, owner, env, depth + 1);
                        }
                    }
                }
            }
            "DMASTList" | "DMASTNewList"
                if f(
                    expr,
                    if kind(expr) == "DMASTList" {
                        "Values"
                    } else {
                        "Parameters"
                    },
                )
                .as_array()
                .is_some_and(Vec::is_empty) =>
            {
                return make(
                    "Empty collection",
                    format!("{}:{}", source(expr).0, source(expr).1),
                    expr,
                );
            }
            "DMASTCall" => {
                return make(
                    "Dynamic call",
                    format!("{}:{}", source(expr).0, source(expr).1),
                    expr,
                )
            }
            _ => {}
        }
        fn first_unknown_child<'a>(
            checker: &Checker<'_>,
            value: &'a Value,
            vars: &HashMap<String, Ty>,
            owner: &str,
            is_root: bool,
        ) -> Option<&'a Value> {
            // A precise child cannot explain why its parent is unresolved.
            // In particular, do not walk every argument below a resolved call:
            // inspect_expr visits those expressions separately.
            if !is_root && is_value_expression(kind(value)) {
                let ty = checker.expression(value, vars, owner);
                return (ty != Ty::Null && !ty.is_precise()).then_some(value);
            }
            if let Some(fields) = value["fields"].as_object() {
                for child in fields.values() {
                    if child.is_object() {
                        if let Some(found) = first_unknown_child(checker, child, vars, owner, false)
                        {
                            return Some(found);
                        }
                    } else if let Some(items) = child.as_array() {
                        for item in items {
                            if let Some(found) =
                                first_unknown_child(checker, item, vars, owner, false)
                            {
                                return Some(found);
                            }
                        }
                    }
                }
            }
            None
        }
        if let Some(child) = first_unknown_child(self, expr, &env.facts, owner, true) {
            return self.unknown_root(child, owner, env, depth + 1);
        }
        make(
            self.unresolved_cause(expr, owner, env),
            format!("{}@{}:{}", kind(expr), source(expr).0, source(expr).1),
            expr,
        )
    }

    fn inspect_contextual_new(&mut self, expr: &Value, owner: &str, env: &Env, expected: &Ty) {
        if contextual_new_type(expr, expected).is_some_and(|ty| ty.is_precise()) {
            if self.strict(expr) {
                self.coverage.typed_expressions += 1;
            }
            // The inferred constructor path is supplied by its destination;
            // its arguments still need their ordinary expression checks.
            let mut current = env.clone();
            for parameter in f(expr, "Parameters").as_array().into_iter().flatten() {
                self.inspect_expr(parameter, owner, &current);
                current.invalidate_after(parameter);
            }
        } else {
            self.inspect_expr(expr, owner, env);
        }
    }

    fn inspect_condition(&mut self, expr: &Value, owner: &str, env: &Env) {
        let logical = matches!(kind(expr), "DMASTAnd" | "DMASTOr");
        let values_known = logical
            && ["LHS", "RHS"].iter().all(|side| {
                let ty = self.expression(f(expr, side), &env.facts, owner);
                ty == Ty::Null || ty.is_precise()
            });
        let result = values_known.then(|| self.expression(expr, &env.facts, owner));
        let condition_only =
            self.strict(expr) && result.is_some_and(|ty| ty != Ty::Null && !ty.is_precise());
        let old_cause = condition_only.then(|| self.unresolved_cause(expr, owner, env).to_owned());
        let old_root = condition_only.then(|| self.unknown_root(expr, owner, env, 0));
        self.inspect_expr(expr, owner, env);
        if let (Some(old_cause), Some(old_root)) = (old_cause, old_root) {
            if let Some(count) = self.coverage.unresolved_causes.get_mut(&old_cause) {
                *count -= 1;
                if *count == 0 {
                    self.coverage.unresolved_causes.remove(&old_cause);
                }
            }
            *self
                .coverage
                .unresolved_causes
                .entry("Condition-only logical value".into())
                .or_default() += 1;
            let old_key = format!("{}\u{1f}{}", old_root.category, old_root.symbol);
            if let Some(count) = self.coverage.unresolved_roots.get_mut(&old_key) {
                count.count -= 1;
                if count.count == 0 {
                    self.coverage.unresolved_roots.remove(&old_key);
                }
            }
            let mut root = old_root;
            root.category = "Condition-only logical value".into();
            let new_key = format!("{}\u{1f}{}", root.category, root.symbol);
            self.coverage
                .unresolved_roots
                .entry(new_key)
                .and_modify(|existing| existing.count += 1)
                .or_insert(root);
        }
    }

    fn inspect_expr(&mut self, expr: &Value, owner: &str, env: &Env) {
        let vars = &env.facts;
        if self.strict(expr) && is_value_expression(kind(expr)) {
            let inferred = self.expression(expr, vars, owner);
            if inferred == Ty::Null || inferred.is_precise() {
                self.coverage.typed_expressions += 1;
            } else {
                self.coverage.unresolved_expressions += 1;
                let cause = self.unresolved_cause(expr, owner, env);
                let root = self.unknown_root(expr, owner, env, 0);
                let root_key = format!("{}\u{1f}{}", root.category, root.symbol);
                self.coverage
                    .unresolved_roots
                    .entry(root_key)
                    .and_modify(|existing| existing.count += 1)
                    .or_insert(root);
                *self
                    .coverage
                    .unresolved_causes
                    .entry(cause.into())
                    .or_default() += 1;
                *self
                    .coverage
                    .unresolved_by_kind
                    .entry(kind(expr).into())
                    .or_default() += 1;
                if kind(expr) == "DMASTIdentifier" {
                    if let Some(name) = f(expr, "Identifier").as_str() {
                        *self
                            .coverage
                            .unresolved_identifiers
                            .entry(name.into())
                            .or_default() += 1;
                    }
                }
            }
        }
        if kind(expr) == "DMASTIdentifier" {
            let name = f(expr, "Identifier").as_str().unwrap_or("");
            if env.slots.contains_key(name) && !env.assigned.contains(name) && self.strict(expr) {
                self.findings.push(issue(
                    expr,
                    "read-before-assignment",
                    format!("{name} is read before it is initialized"),
                ));
            }
        }
        if matches!(
            kind(expr),
            "DMASTNegate"
                | "DMASTBinaryNot"
                | "DMASTPreIncrement"
                | "DMASTPostIncrement"
                | "DMASTPreDecrement"
                | "DMASTPostDecrement"
        ) {
            let operand = self.expression(f(expr, "Value"), vars, owner);
            self.assignment(expr, &Ty::Num, &operand, "numeric operator operand");
        }
        if matches!(
            kind(expr),
            "DMASTBinaryOr" | "DMASTBinaryAnd" | "DMASTBinaryXor" | "DMASTCombine" | "DMASTMask"
        ) {
            let left = self.expression(f(expr, "LHS"), vars, owner);
            let right = self.expression(f(expr, "RHS"), vars, owner);
            if left == Ty::Num && !numeric_operand(&right) {
                self.assignment(expr, &Ty::Num, &right, "bitwise right operand");
            }
        }
        if kind(expr) == "DMASTLocateCoordinates" {
            for axis in ["X", "Y", "Z"] {
                let coordinate = self.expression(f(expr, axis), vars, owner);
                self.assignment(
                    expr,
                    &Ty::Num,
                    &coordinate,
                    &format!("locate {axis} coordinate"),
                );
            }
        }
        if kind(expr) == "DMASTNewModifiedType" {
            if let Some(path) = f(f(f(expr, "Type"), "Value"), "Path").as_str() {
                for entry in f(f(expr, "Type"), "VarOverridesAst")
                    .as_array()
                    .into_iter()
                    .flatten()
                {
                    let value = &entry["value"];
                    self.inspect_expr(value, owner, env);
                    if let Some(name) = entry["name"].as_str() {
                        if let Some(key) = self.field_key(path, name) {
                            let expected = self.fields[&key].ty.clone();
                            let actual = self.expression(value, vars, owner);
                            self.assignment(value, &expected, &actual, &format!("{path}.{name}"));
                        } else if self.strict(expr) {
                            self.findings.push(issue(
                                expr,
                                "unresolved-member-write",
                                format!("{path}.{name} is not a known field"),
                            ));
                        }
                    }
                }
            }
        }
        if let Some(key) = self.reflected_field_key(expr, vars, owner) {
            let base = f(expr, "Expression");
            let bare_vars =
                kind(base) == "DMASTIdentifier" && f(base, "Identifier").as_str() == Some("vars");
            if !bare_vars {
                self.inspect_expr(base, owner, env);
            }
            let receiver = if bare_vars {
                vars.get("src")
                    .cloned()
                    .unwrap_or_else(|| Ty::Path(owner.into()))
            } else {
                self.expression(base, vars, owner)
            };
            let safe = f(expr, "Operations")
                .as_array()
                .and_then(|ops| ops.first())
                .and_then(|op| f(op, "Safe").as_bool())
                .unwrap_or(false);
            if self.strict(expr) {
                if receiver.may_be_null() && !safe {
                    self.findings.push(issue(
                        expr,
                        "strict-null-dereference",
                        format!(
                            "reflected receiver may be null or unresolved ({})",
                            receiver.label()
                        ),
                    ));
                } else {
                    self.coverage.discharged_null_checks += 1;
                }
                if !self.fields[&key].ty.is_precise() {
                    self.findings.push(issue(
                        expr,
                        "unresolved-member-read",
                        format!("reflected field {}.{} has no checked type", key.0, key.1),
                    ));
                }
            }
            return;
        }
        if kind(expr) == "DMASTDereference" {
            let receiver_expr = f(expr, "Expression");
            let receiver = self.expression(receiver_expr, vars, owner);
            let safe = f(expr, "Operations")
                .as_array()
                .and_then(|ops| ops.first())
                .and_then(|op| f(op, "Safe").as_bool())
                .unwrap_or(false);
            if !safe && receiver.may_be_null() && self.strict(expr) {
                self.findings.push(issue(
                    expr,
                    "strict-null-dereference",
                    format!("receiver may be null or unresolved ({})", receiver.label()),
                ));
            }
            if self.strict(expr) && (safe || !receiver.may_be_null()) {
                self.coverage.discharged_null_checks += 1;
            }
            let mut current = receiver.nonnull();
            let mut place_key = place(receiver_expr);
            for (index, op) in f(expr, "Operations")
                .as_array()
                .into_iter()
                .flatten()
                .enumerate()
            {
                let member = f(op, "Identifier").as_str().unwrap_or("");
                let operation_safe = f(op, "Safe").as_bool().unwrap_or(false);
                if index > 0 && current.may_be_null() && !operation_safe && self.strict(expr) {
                    self.findings.push(issue(
                        expr,
                        "strict-null-dereference",
                        format!(
                            "intermediate receiver may be null or unresolved ({})",
                            current.label()
                        ),
                    ));
                }
                current = current.nonnull();
                if kind(op) == "IndexOperation" {
                    place_key = place_key
                        .as_deref()
                        .and_then(|prefix| indexed_place_key(prefix, f(op, "Index")));
                    let key = self.expression(f(op, "Index"), vars, owner);
                    current = match current.nonnull() {
                        Ty::List(value) => {
                            self.assignment(expr, &Ty::Num, &key, "list index");
                            Ty::Nullable(value)
                        }
                        Ty::Assoc(expected, value) | Ty::Alist(expected, value) => {
                            self.assignment(expr, &expected, &key, "association key");
                            Ty::Nullable(value)
                        }
                        Ty::Record(fields) => {
                            let index = f(op, "Index");
                            let value = (kind(index) == "DMASTConstantString")
                                .then(|| f(index, "Value").as_str())
                                .flatten()
                                .and_then(|name| fields.get(name));
                            if let Some((value, _)) = value {
                                Ty::Nullable(Box::new(value.clone()))
                            } else {
                                if self.strict(expr) {
                                    self.findings.push(issue(
                                        expr,
                                        "unresolved-index",
                                        "record key is not a proven named field".into(),
                                    ));
                                }
                                Ty::Unknown
                            }
                        }
                        _ => {
                            if self.strict(expr) {
                                self.findings.push(issue(
                                    expr,
                                    "unresolved-index",
                                    "index target has no checked collection type".into(),
                                ));
                            }
                            Ty::Unknown
                        }
                    };
                    if operation_safe && !current.may_be_null() {
                        current = Ty::Nullable(Box::new(current));
                    }
                    if let Some(fact) = place_key.as_ref().and_then(|key| vars.get(key)) {
                        current = fact.clone();
                    }
                    continue;
                }
                if kind(op) == "FieldOperation" {
                    if let Some(builtin) = collection_field_type(&current, member) {
                        place_key = None;
                        current = if operation_safe {
                            Ty::Nullable(Box::new(builtin))
                        } else {
                            builtin
                        };
                        continue;
                    }
                }
                let Ty::Path(path) = current.clone() else {
                    if self.strict(expr) {
                        let rule = if kind(op) == "CallOperation" {
                            self.coverage.unresolved_calls += 1;
                            "unresolved-member-call"
                        } else {
                            "unresolved-member-read"
                        };
                        self.findings.push(issue(
                            expr,
                            rule,
                            format!(
                                "receiver for {member} has no checked member type ({})",
                                current.label()
                            ),
                        ));
                    }
                    break;
                };
                if kind(op) == "CallOperation" {
                    if let Some(sig) = self.signature(&path, member).cloned() {
                        if self.strict(expr) {
                            self.coverage.resolved_calls += 1;
                        }
                        self.check_arguments(op, &sig, owner, vars, "Parameters");
                        current = sig.result;
                    } else {
                        if self.strict(expr) {
                            self.coverage.unresolved_calls += 1;
                            self.findings.push(issue(
                                expr,
                                "unresolved-member-call",
                                format!("{path}.{member} has no checked signature"),
                            ));
                        }
                        break;
                    }
                } else if kind(op) == "FieldOperation" {
                    current = if let Some(info) = self
                        .field_key(&path, member)
                        .and_then(|key| self.fields.get(&key))
                    {
                        let declared = info.ty.clone();
                        if vars.contains_key(STALE_REFERENCES) {
                            stale_field_after_unknown_effect(&declared)
                        } else {
                            declared
                        }
                    } else if let Some(builtin) = self.inherited_builtin_field_type(&path, member) {
                        builtin
                    } else {
                        if self.strict(expr) {
                            self.findings.push(issue(
                                expr,
                                "unresolved-member-read",
                                format!("{path}.{member} has no checked field type"),
                            ));
                        }
                        Ty::Unknown
                    };
                } else {
                    break;
                }
                if kind(op) == "FieldOperation" {
                    if let Some(key) = place_key.as_mut() {
                        key.push('.');
                        key.push_str(member);
                        if let Some(fact) = vars.get(key) {
                            current = fact.clone();
                        }
                    }
                } else {
                    place_key = None;
                }
                if operation_safe && !current.may_be_null() {
                    current = Ty::Nullable(Box::new(current));
                }
            }
        }
        if kind(expr) == "DMASTProcCall" {
            let callable = f(expr, "Callable");
            if kind(callable) == "DMASTCallableSuper" {
                let signature = self
                    .current_proc
                    .as_ref()
                    .and_then(|name| self.parent_signature(owner, name))
                    .cloned();
                if let Some(sig) = signature {
                    if self.strict(expr) {
                        self.coverage.resolved_calls += 1;
                    }
                    if f(expr, "Parameters")
                        .as_array()
                        .is_some_and(|arguments| !arguments.is_empty())
                    {
                        self.check_arguments(expr, &sig, owner, vars, "Parameters");
                    }
                } else if self.strict(expr) {
                    self.coverage.unresolved_calls += 1;
                    self.findings.push(issue(
                        expr,
                        "unresolved-parent-call",
                        "parent call has no checked signature".into(),
                    ));
                }
            } else if kind(callable) == "DMASTCallableProcIdentifier" {
                let name = f(callable, "Identifier").as_str().unwrap_or("");
                if matches!(name, "islist" | "isnum" | "istext") {
                    if self.strict(expr) {
                        if checked_unary_builtin(expr) {
                            self.coverage.resolved_calls += 1;
                        } else {
                            self.coverage.unresolved_calls += 1;
                            self.findings.push(issue(
                                expr,
                                "unresolved-direct-call",
                                format!("{name} needs one positional argument"),
                            ));
                        }
                    }
                } else if name == "ispath" {
                    if self.strict(expr) {
                        if checked_ispath_builtin(expr) {
                            self.coverage.resolved_calls += 1;
                        } else {
                            self.coverage.unresolved_calls += 1;
                            self.findings.push(issue(
                                expr,
                                "unresolved-direct-call",
                                "ispath needs one value and an optional literal type path".into(),
                            ));
                        }
                    }
                } else if matches!(name, "typesof" | "subtypesof") {
                    if self.strict(expr) {
                        if self.type_enumeration_result(expr, vars, owner).is_precise() {
                            self.coverage.resolved_calls += 1;
                        } else {
                            self.coverage.unresolved_calls += 1;
                            self.findings.push(issue(
                                expr,
                                "unresolved-type-enumeration",
                                format!("{name} needs proved type path arguments"),
                            ));
                        }
                    }
                } else {
                    if name == "arglist"
                        && self.strict(expr)
                        && !self.validated_admin_wrapper(owner)
                    {
                        self.coverage.dynamic_operations += 1;
                        self.coverage.unresolved_calls += 1;
                        self.findings.push(issue(
                        expr,
                        "unresolved-argument-pack",
                        "arglist() needs a validated argument count and element types at its call site".into(),
                    ));
                    }
                    let builtin = self
                        .signature(owner, name)
                        .filter(|signature| !standard_builtin_signature(signature))
                        .is_none()
                        .then(|| self.builtin_result(expr, name, vars, owner))
                        .flatten();
                    if let Some(result) = builtin {
                        if self.strict(expr) {
                            if result.is_precise() {
                                self.coverage.resolved_calls += 1;
                            } else {
                                self.coverage.unresolved_calls += 1;
                                self.findings.push(issue(
                                    expr,
                                    "unresolved-direct-call",
                                    format!("{name} arguments do not prove one result type"),
                                ));
                            }
                        }
                        if name == "round" {
                            for argument in f(expr, "Parameters").as_array().into_iter().flatten() {
                                let value = f(argument, "Value");
                                let actual = self.expression(value, vars, owner);
                                self.assignment(expr, &Ty::Num, &actual, "round argument");
                            }
                        }
                        if matches!(
                            name,
                            "view"
                                | "oview"
                                | "range"
                                | "orange"
                                | "viewers"
                                | "oviewers"
                                | "hearers"
                                | "ohearers"
                        ) {
                            for argument in f(expr, "Parameters").as_array().into_iter().flatten() {
                                let actual = self.expression(f(argument, "Value"), vars, owner);
                                let valid = matches!(actual, Ty::Num | Ty::Text)
                                    || matches!(&actual, Ty::Path(path)
                                        if self.symbols.is_subtype(path, "/atom"));
                                if self.strict(expr) && !valid {
                                    self.findings.push(issue(expr, "unresolved-spatial-argument",
                                        format!("{name} argument needs a distance or atom type; found {}", actual.label())));
                                }
                            }
                        }
                    } else if let Some(sig) = self.signature(owner, name).cloned() {
                        if self.strict(expr) {
                            self.coverage.resolved_calls += 1;
                        }
                        self.check_arguments(expr, &sig, owner, vars, "Parameters");
                    } else if name != "arglist"
                        && self.strict(expr)
                        && !["isnull", "istype", "ispath", "QDELETED", "length"].contains(&name)
                    {
                        self.coverage.unresolved_calls += 1;
                        self.findings.push(issue(
                            expr,
                            "unresolved-direct-call",
                            format!("{name} has no checked signature in {owner}"),
                        ));
                    }
                }
            }
        }
        if kind(expr) == "DMASTCall" && self.strict(expr) {
            self.coverage.dynamic_operations += 1;
            if let Some(args) = f(expr, "CallParameters").as_array() {
                if args.len() == 2 {
                    let receiver = self.expression(f(&args[0], "Value"), vars, owner);
                    if receiver.may_be_null() {
                        self.findings.push(issue(
                            expr,
                            "strict-null-dereference",
                            format!(
                                "dynamic call receiver may be null or unresolved ({})",
                                receiver.label()
                            ),
                        ));
                    } else {
                        self.coverage.discharged_null_checks += 1;
                    }
                }
            }
            if let Some(sig) = self.dynamic_signature(expr, vars, owner) {
                self.coverage.resolved_calls += 1;
                self.check_arguments(expr, &sig, owner, vars, "ProcParameters");
            } else {
                self.coverage.unresolved_calls += 1;
                self.findings.push(issue(
                    expr,
                    "unresolved-dynamic-call",
                    "call() target or signature is not statically resolved".into(),
                ));
            }
        }
        if matches!(kind(expr), "DMASTAnd" | "DMASTOr") {
            let lhs = f(expr, "LHS");
            let rhs = f(expr, "RHS");
            self.inspect_expr(lhs, owner, env);
            let mut guarded = env.clone();
            guarded.invalidate_after(lhs);
            if !contains_unknown_effect(lhs) {
                seed_guard_facts(lhs, &mut guarded.facts, self, owner);
                narrow_env(lhs, kind(expr) == "DMASTAnd", &mut guarded);
            }
            self.inspect_expr(rhs, owner, &guarded);
            return;
        }
        if kind(expr) == "DMASTTernary" {
            let condition = f(expr, "A");
            self.inspect_condition(condition, owner, env);
            let mut base = env.clone();
            base.invalidate_after(condition);
            let mut yes = base.clone();
            let mut no = base;
            if !contains_unknown_effect(condition) {
                seed_guard_facts(condition, &mut yes.facts, self, owner);
                seed_guard_facts(condition, &mut no.facts, self, owner);
                narrow_env(condition, true, &mut yes);
                narrow_env(condition, false, &mut no);
            }
            self.inspect_expr(f(expr, "B"), owner, &yes);
            self.inspect_expr(f(expr, "C"), owner, &no);
            return;
        }
        if let Some(fields) = expr["fields"].as_object() {
            if let (Some(lhs), Some(rhs)) = (fields.get("LHS"), fields.get("RHS")) {
                self.inspect_expr(lhs, owner, env);
                let mut after_left = env.clone();
                after_left.invalidate_after(lhs);
                self.inspect_expr(rhs, owner, &after_left);
                return;
            }
            for child in fields.values() {
                if let Some(items) = child.as_array() {
                    let mut current = env.clone();
                    for item in items {
                        if item.is_object() {
                            self.inspect_expr(item, owner, &current);
                            current.invalidate_after(item);
                        }
                    }
                } else if child.is_object() {
                    self.inspect_expr(child, owner, env);
                }
            }
        }
    }

    fn check_arguments(
        &mut self,
        node: &Value,
        sig: &Signature,
        owner: &str,
        vars: &HashMap<String, Ty>,
        argument_field: &str,
    ) {
        let Some(args) = f(node, argument_field).as_array() else {
            return;
        };
        let mut passed = HashSet::new();
        let mut positional = 0usize;
        let mut has_pack = false;
        let mut current_vars = vars.clone();
        for arg in args {
            let value = f(arg, "Value");
            let key_node = f(arg, "Key");
            invalidate_after(key_node, &mut current_vars);
            let actual = self.expression(value, &current_vars, owner);
            invalidate_after(value, &mut current_vars);
            if kind(value) == "DMASTProcCall"
                && f(f(value, "Callable"), "Identifier").as_str() == Some("arglist")
            {
                has_pack = true;
                let generated_dispatch = self.validated_admin_wrapper(owner)
                    && f(node, "Identifier").as_str() == Some("dynamic_invoke_verb");
                if self.strict(node) && !generated_dispatch {
                    self.findings.push(issue(
                        node,
                        "unresolved-argument-pack",
                        "arglist() argument expansion cannot be matched to this signature".into(),
                    ));
                }
                continue;
            }
            let key = key_node.as_str().or_else(|| {
                if kind(key_node) == "DMASTConstantString" {
                    f(key_node, "Value").as_str()
                } else {
                    None
                }
            });
            if !key_node.is_null() && key.is_none() {
                has_pack = true;
                if self.strict(node) {
                    self.findings.push(issue(
                        arg,
                        "unresolved-argument-key",
                        "computed argument key cannot be matched to a parameter".into(),
                    ));
                }
                continue;
            }
            let param = if let Some(key) = key {
                sig.parameters.iter().find(|p| p.name == key)
            } else {
                let result = sig.parameters.get(positional);
                positional += 1;
                result
            };
            if let Some(param) = param {
                if !passed.insert(param.name.clone()) && self.strict(node) {
                    self.findings.push(issue(
                        node,
                        "duplicate-argument",
                        format!("{} is supplied more than once", param.name),
                    ));
                }
                let actual = if self.literal_collection_accepts(&param.ty, value, owner) {
                    param.ty.nonnull()
                } else {
                    actual
                };
                self.assignment(arg, &param.ty, &actual, &format!("argument {}", param.name));
            } else if self.strict(node) {
                self.findings.push(issue(
                    arg,
                    "unknown-argument-target",
                    "argument has no resolved parameter".into(),
                ));
            }
        }
        for param in &sig.parameters {
            if has_pack {
                break;
            }
            if !passed.contains(&param.name) && !param.has_default {
                self.assignment(
                    node,
                    &param.ty,
                    &Ty::Null,
                    &format!("omitted argument {}", param.name),
                );
            }
        }
    }

    fn loop_block(&mut self, block: &Value, owner: &str, sig: &Signature, entry: Env) -> LoopFlow {
        let mut flow = LoopFlow {
            next: Some(entry),
            ..LoopFlow::default()
        };
        let Some(statements) = f(block, "Statements").as_array() else {
            return flow;
        };
        for statement in statements {
            let Some(mut current) = flow.next.take() else {
                break;
            };
            match kind(statement) {
                "DMASTProcStatementBreak" | "DMASTProcStatementContinue"
                    if f(statement, "Label").is_null() =>
                {
                    if kind(statement) == "DMASTProcStatementBreak" {
                        flow.breaks.push(current);
                    } else {
                        flow.continues.push(current);
                    }
                }
                "DMASTProcStatementIf" => {
                    let condition = f(statement, "Condition");
                    self.inspect_condition(condition, owner, &current);
                    current.invalidate_after(condition);
                    invalidate_result_after(condition, &mut current.result_fact);
                    let stable = !contains_unknown_effect(condition);
                    if stable {
                        seed_guard_facts(condition, &mut current.facts, self, owner);
                    }
                    let mut yes = current.clone();
                    let mut no = current;
                    if stable {
                        narrow_env(condition, true, &mut yes);
                        narrow_env(condition, false, &mut no);
                    }
                    let yes_flow = self.loop_block(f(statement, "Body"), owner, sig, yes);
                    let no_flow = if f(statement, "ElseBody").is_null() {
                        LoopFlow {
                            next: Some(no),
                            ..LoopFlow::default()
                        }
                    } else {
                        self.loop_block(f(statement, "ElseBody"), owner, sig, no)
                    };
                    if self.strict(statement) {
                        if let (Some(yes_state), Some(no_state)) =
                            (yes_flow.next.as_ref(), no_flow.next.as_ref())
                        {
                            for (local, yes_type) in &yes_state.slots {
                                if let Some(no_type) = no_state.slots.get(local) {
                                    if yes_type != no_type
                                        && yes_type.is_precise()
                                        && no_type.is_precise()
                                        && matches!(
                                            yes_type.join(no_type, self.symbols),
                                            Ty::Unknown | Ty::OneOf(_)
                                        )
                                    {
                                        self.findings.push(issue(
                                            statement,
                                            "local-type-conflict",
                                            format!(
                                                "{local} receives {} and {} on different paths",
                                                yes_type.label(),
                                                no_type.label()
                                            ),
                                        ));
                                    }
                                }
                            }
                        }
                    }
                    flow.breaks.extend(yes_flow.breaks);
                    flow.breaks.extend(no_flow.breaks);
                    flow.continues.extend(yes_flow.continues);
                    flow.continues.extend(no_flow.continues);
                    flow.next = merge_envs(
                        yes_flow.next.into_iter().chain(no_flow.next).collect(),
                        self.symbols,
                    );
                }
                _ => {
                    if !self.statement(statement, owner, sig, &mut current) {
                        flow.next = Some(current);
                    }
                }
            }
        }
        flow
    }

    fn preview_loop_block(
        &mut self,
        block: &Value,
        owner: &str,
        sig: &Signature,
        entry: Env,
    ) -> LoopFlow {
        let findings_before = self.findings.len();
        // A preview contributes no coverage. Moving the accumulated counts out
        // avoids copying the (potentially very large) root-cause map per loop.
        let coverage_before = std::mem::take(&mut self.coverage);
        let flow = self.loop_block(block, owner, sig, entry);
        self.findings.truncate(findings_before);
        self.coverage = coverage_before;
        flow
    }

    fn statement(&mut self, node: &Value, owner: &str, sig: &Signature, env: &mut Env) -> bool {
        match kind(node) {
            "DMASTProcStatementVarDeclaration" => {
                let name = f(node, "Name").as_str().unwrap_or("");
                let initializer = f(node, "Value");
                let native = declared(f(node, "Type"), f(node, "ValueType"));
                let actual = if initializer.is_null() {
                    if f(node, "IsGlobal").as_bool() == Some(true) {
                        if native == Ty::Unknown {
                            Ty::Unknown
                        } else {
                            with_nullable(native.clone(), true)
                        }
                    } else {
                        Ty::Null
                    }
                } else {
                    contextual_new_type(initializer, &native)
                        .unwrap_or_else(|| self.expression(initializer, &env.facts, owner))
                };
                let record_fact = self.literal_record_fact(initializer, &env.facts, owner);
                let record_aliases = env.record_references(initializer);
                env.escape_fresh_references(initializer);
                self.inspect_contextual_new(initializer, owner, env, &native);
                let fresh_constructor = kind(initializer) == "DMASTNewInferred"
                    && matches!(&native, Ty::Path(path) if self.symbols.fresh_constructor_preserves_existing(path))
                    && f(initializer, "Parameters")
                        .as_array()
                        .is_some_and(|parameters| {
                            parameters
                                .iter()
                                .all(|parameter| !contains_unknown_effect(parameter))
                        });
                if !fresh_constructor {
                    env.invalidate_after_checked(initializer, owner, self.symbols);
                }
                env.invalidate_record_aliases(initializer, &record_aliases);
                invalidate_result_after(initializer, &mut env.result_fact);
                let hint = self.current_proc.as_deref().and_then(|proc_name| {
                    annotated_type(
                        self.contracts,
                        owner,
                        proc_name,
                        Visibility::LocalType,
                        Some(name),
                    )
                });
                if let Some(hint) = &hint {
                    if self.strict(node) && !hint.is_precise() {
                        self.findings.push(issue(
                            node,
                            "invalid-local-type-contract",
                            format!("{name} has an imprecise local type contract"),
                        ));
                    }
                    if native.is_precise() && !native.accepts(hint, self.symbols) {
                        self.findings.push(issue(
                            node,
                            "incompatible-local-type-contract",
                            format!(
                                "{name} contract {} conflicts with DM type {}",
                                hint.label(),
                                native.label()
                            ),
                        ));
                    }
                }
                let had_hint = hint.is_some();
                let native_unknown = native == Ty::Unknown;
                let ty = if let Some(hint) = hint {
                    hint
                } else if native == Ty::Unknown {
                    self.inferred_locals.get(name).cloned().unwrap_or_else(|| {
                        if actual != Ty::Null {
                            actual.clone()
                        } else {
                            native
                        }
                    })
                } else {
                    native
                };
                let ty = if matches!(ty, Ty::Record(_)) && !had_hint && native_unknown {
                    Ty::Unknown
                } else {
                    ty
                };
                if self.strict(node) && !name.is_empty() {
                    self.coverage.strict_declarations += 1;
                    if ty.is_precise() {
                        self.coverage.known_declarations += 1;
                    } else {
                        self.coverage.unresolved_declarations += 1;
                        self.findings.push(issue(
                            node,
                            "unknown-local-type",
                            format!("{name} has no proven precise single storage type"),
                        ));
                    }
                }
                if !initializer.is_null() && ty != Ty::Unknown {
                    self.assignment(node, &ty, &actual, name);
                }
                let fact = if record_aliases.is_empty() {
                    record_fact.unwrap_or_else(|| contextual_empty_list(actual, &ty))
                } else {
                    Ty::Unknown
                };
                env.origins.insert(name.into(), source(node));
                env.slots.insert(name.into(), ty);
                env.record_fact_origin(name, &fact, node);
                let fresh = matches!(fact, Ty::EmptyList | Ty::EmptyAlist);
                overwrite_place_fact(&mut env.facts, name, fact);
                if fresh {
                    env.fresh_collections.insert(name.into());
                } else {
                    env.fresh_collections.remove(name);
                }
                if !initializer.is_null() || f(node, "IsGlobal").as_bool() == Some(true) {
                    env.assigned.insert(name.into());
                }
                false
            }
            "DMASTProcStatementExpression" => {
                let expr = f(node, "Expression");
                if kind(expr) == "DMASTAssign" {
                    let lhs = f(expr, "LHS");
                    let rhs = f(expr, "RHS");
                    let expected_new = if kind(lhs) == "DMASTIdentifier" {
                        f(lhs, "Identifier").as_str().and_then(|name| {
                            env.slots.get(name).cloned().or_else(|| {
                                self.field_key(owner, name)
                                    .and_then(|key| self.fields.get(&key))
                                    .map(|field| field.ty.clone())
                            })
                        })
                    } else {
                        None
                    };
                    if let Some(expected) = &expected_new {
                        self.inspect_contextual_new(rhs, owner, env, expected);
                    } else {
                        self.inspect_expr(rhs, owner, env);
                    }
                    let actual = expected_new
                        .as_ref()
                        .and_then(|expected| contextual_new_type(rhs, expected))
                        .unwrap_or_else(|| self.expression(rhs, &env.facts, owner));
                    let record_fact = self.literal_record_fact(rhs, &env.facts, owner);
                    let record_aliases = env.record_references(rhs);
                    env.escape_fresh_references(rhs);
                    env.invalidate_after_checked(rhs, owner, self.symbols);
                    env.invalidate_record_aliases(rhs, &record_aliases);
                    let actual = if record_aliases.is_empty() {
                        actual
                    } else {
                        Ty::Unknown
                    };
                    invalidate_result_after(rhs, &mut env.result_fact);
                    if kind(lhs) == "DMASTIdentifier" {
                        let name = f(lhs, "Identifier").as_str().unwrap_or("");
                        if let Some(expected) = env.slots.get(name).cloned() {
                            let actual = if kind(rhs) == "DMASTNewInferred" {
                                match &expected {
                                    Ty::Path(_) => expected.clone(),
                                    _ => actual,
                                }
                            } else {
                                actual
                            };
                            let stable = if expected == Ty::Unknown
                                && actual != Ty::Null
                                && !matches!(actual, Ty::Record(_))
                            {
                                actual.clone()
                            } else {
                                expected
                            };
                            self.assignment(expr, &stable, &actual, name);
                            let fact = if record_aliases.is_empty() {
                                record_fact
                                    .unwrap_or_else(|| contextual_empty_list(actual, &stable))
                            } else {
                                Ty::Unknown
                            };
                            env.slots.insert(name.into(), stable);
                            env.record_fact_origin(name, &fact, expr);
                            let fresh = matches!(fact, Ty::EmptyList | Ty::EmptyAlist);
                            env.facts.insert(name.into(), fact);
                            if fresh {
                                env.fresh_collections.insert(name.into());
                            } else {
                                env.fresh_collections.remove(name);
                            }
                            let prefix = format!("{name}.");
                            env.facts.retain(|key, _| !key.starts_with(&prefix));
                            env.assigned.insert(name.into());
                        } else if let Some(key) = self.field_key(owner, name) {
                            let field = self.fields[&key].clone();
                            let actual = if self.literal_collection_accepts(&field.ty, rhs, owner) {
                                field.ty.nonnull()
                            } else if kind(rhs) == "DMASTNewInferred"
                                && matches!(field.ty, Ty::Path(_))
                            {
                                field.ty.clone()
                            } else {
                                actual
                            };
                            let selected = self.strict(expr)
                                || self.selection.includes(source(&field.origin).0.as_str());
                            self.assignment_with_policy(
                                expr,
                                &field.ty,
                                &actual,
                                &format!("{owner}.{name}"),
                                selected,
                            );
                            let prefix = format!("{name}.");
                            env.facts
                                .retain(|key, _| key != name && !key.starts_with(&prefix));
                            env.record_fact_origin(name, &actual, expr);
                            env.facts.insert(name.into(), actual);
                        }
                    } else if kind(lhs) == "DMASTCallableSelf" {
                        env.result_fact = actual.clone();
                        if sig.result_required {
                            self.assignment(expr, &sig.result, &actual, "implicit result");
                        }
                    } else if kind(lhs) == "DMASTDereference" {
                        let mut assignment_fact = actual.clone();
                        if let Some([index]) = f(lhs, "Operations").as_array().map(Vec::as_slice) {
                            if kind(index) == "IndexOperation" {
                                let base = f(lhs, "Expression");
                                if let Some(base_name) =
                                    place(base).filter(|name| env.slots.contains_key(name))
                                {
                                    if let Some(Ty::Record(mut fields)) =
                                        env.facts.get(&base_name).cloned()
                                    {
                                        let index_expr = f(index, "Index");
                                        self.inspect_expr(base, owner, env);
                                        self.inspect_expr(index_expr, owner, env);
                                        let key = (kind(index_expr) == "DMASTConstantString")
                                            .then(|| f(index_expr, "Value").as_str())
                                            .flatten();
                                        if let Some(key) = key {
                                            // A value of unknown type spoils only this
                                            // named entry. Other constant-key entries of a
                                            // fresh, unescaped record retain their proofs.
                                            fields.insert(key.into(), (actual.clone(), false));
                                            let fact = Ty::Record(fields);
                                            env.record_fact_origin(&base_name, &fact, expr);
                                            overwrite_place_fact(&mut env.facts, &base_name, fact);
                                            if let Some(entry_key) = place(lhs) {
                                                env.facts.insert(entry_key, actual);
                                            }
                                        } else {
                                            env.record_fact_origin(&base_name, &Ty::Unknown, expr);
                                            overwrite_place_fact(
                                                &mut env.facts,
                                                &base_name,
                                                Ty::Unknown,
                                            );
                                        }
                                        return false;
                                    }
                                }
                            }
                        }
                        if let Some(key) = self.reflected_field_key(lhs, &env.facts, owner) {
                            let info = self.fields[&key].clone();
                            let actual = if self.literal_collection_accepts(&info.ty, rhs, owner) {
                                info.ty.nonnull()
                            } else if kind(rhs) == "DMASTNewInferred"
                                && matches!(info.ty, Ty::Path(_))
                            {
                                info.ty.clone()
                            } else {
                                actual
                            };
                            let selected = self.strict(expr)
                                || self.selection.includes(source(&info.origin).0.as_str());
                            self.assignment_with_policy(
                                expr,
                                &info.ty,
                                &actual,
                                &format!("reflected {}.{}", key.0, key.1),
                                selected,
                            );
                            self.inspect_expr(lhs, owner, env);
                            env.facts.retain(|name, _| {
                                name != &key.1 && !name.starts_with(&format!("{}.", key.1))
                            });
                            return false;
                        }
                        let receiver = self
                            .expression(f(lhs, "Expression"), &env.facts, owner)
                            .nonnull();
                        let operations = f(lhs, "Operations").as_array();
                        let operation = operations.and_then(|ops| ops.first());
                        if let Some(op) = operation.filter(|op| kind(op) == "IndexOperation") {
                            let key = self.expression(f(op, "Index"), &env.facts, owner);
                            let local = place(f(lhs, "Expression"))
                                .filter(|name| env.slots.contains_key(name));
                            let mut invalidate_shape = false;
                            match &receiver {
                                Ty::EmptyList => {
                                    let index = f(op, "Index");
                                    let shape = if kind(index) == "DMASTConstantString"
                                        && actual.is_precise()
                                    {
                                        f(index, "Value").as_str().map(|name| {
                                            Ty::Record(BTreeMap::from([(
                                                name.into(),
                                                (actual.clone(), actual.may_be_null()),
                                            )]))
                                        })
                                    } else {
                                        None
                                    };
                                    let shape = shape.or_else(|| match (&key, &actual) {
                                        (Ty::Num, value)
                                            if value.is_precise() && !value.may_be_null() =>
                                        {
                                            Some(Ty::List(Box::new(value.clone())))
                                        }
                                        (Ty::Text, value)
                                            if value.is_precise() && !value.may_be_null() =>
                                        {
                                            Some(Ty::Assoc(
                                                Box::new(Ty::Text),
                                                Box::new(value.clone()),
                                            ))
                                        }
                                        (Ty::Nullable(inner), value)
                                            if **inner == Ty::Text
                                                && value.is_precise()
                                                && !value.may_be_null() =>
                                        {
                                            Some(Ty::Assoc(
                                                Box::new(key.clone()),
                                                Box::new(value.clone()),
                                            ))
                                        }
                                        _ => None,
                                    });
                                    if let (Some(local), Some(shape)) = (
                                        local
                                            .as_ref()
                                            .filter(|name| env.fresh_collections.contains(*name)),
                                        shape,
                                    ) {
                                        overwrite_place_fact(&mut env.facts, local, shape);
                                    } else if self.strict(expr) {
                                        self.findings.push(issue(
                                            expr,
                                            "unresolved-index-write",
                                            "fresh list write has no proved key and element types"
                                                .into(),
                                        ));
                                        invalidate_shape = true;
                                    }
                                }
                                Ty::List(element) => {
                                    self.assignment(expr, &Ty::Num, &key, "list index");
                                    self.assignment(expr, element, &actual, "list element");
                                    invalidate_shape = !Ty::Num.accepts(&key, self.symbols)
                                        || !element.accepts(&actual, self.symbols)
                                        || key.has_unknown()
                                        || actual.has_unknown();
                                }
                                Ty::Assoc(key_ty, value_ty) | Ty::Alist(key_ty, value_ty) => {
                                    self.assignment(expr, key_ty, &key, "association key");
                                    self.assignment(expr, value_ty, &actual, "association value");
                                    invalidate_shape = !key_ty.accepts(&key, self.symbols)
                                        || !value_ty.accepts(&actual, self.symbols)
                                        || key.has_unknown()
                                        || actual.has_unknown();
                                }
                                _ => {
                                    if self.strict(expr) {
                                        self.findings.push(issue(
                                            expr,
                                            "unresolved-index-write",
                                            "indexed write has no checked collection type".into(),
                                        ));
                                    }
                                    if let Some(place) = place(f(lhs, "Expression")) {
                                        env.facts.insert(place, Ty::Unknown);
                                    }
                                }
                            }
                            if invalidate_shape {
                                if let Some(local) = local {
                                    overwrite_place_fact(&mut env.facts, &local, Ty::Unknown);
                                }
                            }
                        }
                        let member = operation
                            .filter(|op| kind(op) == "FieldOperation")
                            .and_then(|op| f(op, "Identifier").as_str());
                        if let (Ty::Path(receiver), Some(member), Some(operations)) =
                            (receiver, member, operations)
                        {
                            if let Some(key) = self.field_key(&receiver, member) {
                                let info = self.fields[&key].clone();
                                let selected = self.strict(expr)
                                    || self.selection.includes(source(&info.origin).0.as_str());
                                if operations.len() == 1 {
                                    let actual =
                                        if self.literal_collection_accepts(&info.ty, rhs, owner) {
                                            info.ty.nonnull()
                                        } else if kind(rhs) == "DMASTNewInferred" {
                                            match &info.ty {
                                                Ty::Path(_) => info.ty.clone(),
                                                _ => actual.clone(),
                                            }
                                        } else {
                                            actual.clone()
                                        };
                                    assignment_fact =
                                        contextual_empty_list(actual.clone(), &info.ty);
                                    self.assignment_with_policy(
                                        expr,
                                        &info.ty,
                                        &actual,
                                        &format!("{receiver}.{member}"),
                                        selected,
                                    );
                                } else if operations.len() == 2
                                    && kind(&operations[1]) == "IndexOperation"
                                {
                                    let place_key = place(f(lhs, "Expression"))
                                        .map(|base| format!("{base}.{member}"));
                                    let target_ty = place_key
                                        .as_ref()
                                        .and_then(|name| env.facts.get(name))
                                        .cloned()
                                        .unwrap_or_else(|| info.ty.clone());
                                    let index_ty = self.expression(
                                        f(&operations[1], "Index"),
                                        &env.facts,
                                        owner,
                                    );
                                    match target_ty.nonnull() {
                                        Ty::List(element) => {
                                            self.assignment_with_policy(expr, &Ty::Num, &index_ty, "list index", selected);
                                            self.assignment_with_policy(expr, &element, &actual, "list element", selected);
                                        }
                                        Ty::Assoc(key_ty, value_ty) | Ty::Alist(key_ty, value_ty) => {
                                            self.assignment_with_policy(expr, &key_ty, &index_ty, "association key", selected);
                                            self.assignment_with_policy(expr, &value_ty, &actual, "association value", selected);
                                        }
                                        Ty::Record(fields) => {
                                            let index = f(&operations[1], "Index");
                                            let expected = (kind(index) == "DMASTConstantString")
                                                .then(|| f(index, "Value").as_str())
                                                .flatten()
                                                .and_then(|name| fields.get(name));
                                            if let Some((value_ty, _)) = expected {
                                                self.assignment_with_policy(expr, value_ty, &actual, "record field", selected);
                                            } else if selected {
                                                self.findings.push(issue(expr, "unresolved-index-write",
                                                    "record write key is not a proven named field".into()));
                                            }
                                        }
                                        _ if selected => self.findings.push(issue(
                                            expr, "unresolved-index-write",
                                            format!("{receiver}.{member} has no checked collection type"),
                                        )),
                                        _ => {}
                                    }
                                } else if selected {
                                    self.findings.push(issue(
                                        expr, "unresolved-index-write",
                                        format!("chained write to {receiver}.{member} is not yet modeled"),
                                    ));
                                }
                            }
                        }
                        self.inspect_expr(lhs, owner, env);
                        env.facts.retain(|key, _| !key.contains('.'));
                        if let Some(key) = place(lhs) {
                            env.facts.insert(key, assignment_fact);
                        }
                    }
                } else {
                    let mut proved_scalar_append = false;
                    let mut proved_local_list_append = None;
                    if kind(expr) == "DMASTAppend" {
                        let lhs = f(expr, "LHS");
                        let rhs = f(expr, "RHS");
                        let destination = self.expression(lhs, &env.facts, owner);
                        let appended = self.expression(rhs, &env.facts, owner);
                        proved_scalar_append = matches!(
                            (&destination, &appended),
                            (Ty::Num, Ty::Num) | (Ty::Text, Ty::Text)
                        ) && !contains_unknown_effect(lhs)
                            && !contains_unknown_effect(rhs);
                        if let Ty::List(element) = &destination {
                            let compatible = match &appended {
                                Ty::List(other) => element == other && element.is_precise(),
                                other => {
                                    !matches!(other, Ty::Assoc(_, _))
                                        && element.as_ref() == other
                                        && other.is_precise()
                                }
                            };
                            if compatible
                                && !contains_unknown_effect(lhs)
                                && !contains_unknown_effect(rhs)
                            {
                                if let Some(name) =
                                    place(lhs).filter(|name| env.slots.contains_key(name))
                                {
                                    proved_local_list_append = Some((name, destination.clone()));
                                }
                            }
                        }
                        match destination.nonnull() {
                            Ty::List(element) => match appended {
                                Ty::List(_) => self.assignment(
                                    expr,
                                    &Ty::List(element),
                                    &appended,
                                    "list concatenation",
                                ),
                                _ => self.assignment(expr, &element, &appended, "list append"),
                            },
                            Ty::Num => self.assignment(expr, &Ty::Num, &appended, "numeric append"),
                            Ty::Text => self.assignment(expr, &Ty::Text, &appended, "text append"),
                            _ if self.strict(expr) => self.findings.push(issue(
                                expr,
                                "unresolved-append-target",
                                "compound addition target has no checked type".into(),
                            )),
                            _ => {}
                        }
                    }
                    self.inspect_expr(expr, owner, env);
                    if !proved_scalar_append {
                        env.invalidate_after_checked(expr, owner, self.symbols);
                        invalidate_result_after(expr, &mut env.result_fact);
                        if let Some((name, ty)) = proved_local_list_append {
                            env.facts.insert(name, ty);
                        }
                    }
                }
                false
            }
            "DMASTProcStatementReturn" => {
                let expr = f(node, "Value");
                let actual = if expr.is_null() || kind(expr) == "DMASTCallableSelf" {
                    env.result_fact.clone()
                } else {
                    self.expression(expr, &env.facts, owner)
                };
                self.inspect_expr(expr, owner, env);
                if sig.result_required {
                    self.assignment(node, &sig.result, &actual, "return");
                }
                true
            }
            "DMASTProcStatementIf" => {
                let condition = f(node, "Condition");
                self.inspect_condition(condition, owner, env);
                env.invalidate_after_checked(condition, owner, self.symbols);
                invalidate_result_after(condition, &mut env.result_fact);
                let stable_condition = !contains_unknown_effect(condition);
                if stable_condition {
                    seed_guard_facts(condition, &mut env.facts, self, owner);
                }
                let mut yes = env.clone();
                let mut no = env.clone();
                if stable_condition {
                    narrow_env(condition, true, &mut yes);
                    narrow_env(condition, false, &mut no);
                }
                let yes_exits = self.block(f(node, "Body"), owner, sig, &mut yes);
                let no_exits = if f(node, "ElseBody").is_null() {
                    false
                } else {
                    self.block(f(node, "ElseBody"), owner, sig, &mut no)
                };
                if !yes_exits && !no_exits && self.strict(node) {
                    for (local, yes_type) in &yes.slots {
                        if let Some(no_type) = no.slots.get(local) {
                            if yes_type != no_type
                                && yes_type.is_precise()
                                && no_type.is_precise()
                                && matches!(
                                    yes_type.join(no_type, self.symbols),
                                    Ty::Unknown | Ty::OneOf(_)
                                )
                            {
                                self.findings.push(issue(
                                    node,
                                    "local-type-conflict",
                                    format!(
                                        "{local} receives {} and {} on different paths",
                                        yes_type.label(),
                                        no_type.label()
                                    ),
                                ));
                            }
                        }
                    }
                }
                *env = if yes_exits {
                    no
                } else if no_exits {
                    yes
                } else {
                    Env {
                        slots: join_env(&yes.slots, &no.slots, self.symbols),
                        facts: join_env(&yes.facts, &no.facts, self.symbols),
                        origins: yes
                            .origins
                            .iter()
                            .filter(|(name, origin)| no.origins.get(*name) == Some(*origin))
                            .map(|(name, origin)| (name.clone(), origin.clone()))
                            .collect(),
                        assigned: yes.assigned.intersection(&no.assigned).cloned().collect(),
                        fresh_collections: yes
                            .fresh_collections
                            .intersection(&no.fresh_collections)
                            .cloned()
                            .collect(),
                        result_fact: yes.result_fact.join(&no.result_fact, self.symbols),
                    }
                };
                yes_exits && no_exits
            }
            "DMASTProcStatementSwitch" => {
                let value = f(node, "Value");
                self.inspect_expr(value, owner, env);
                env.invalidate_after_checked(value, owner, self.symbols);
                invalidate_result_after(value, &mut env.result_fact);
                let Some(cases) = f(node, "Cases").as_array() else {
                    if self.strict(node) {
                        self.coverage.unverified_control_flow += 1;
                        self.findings.push(issue(
                            node,
                            "unverified-control-flow",
                            "switch cases are missing from the OpenDream export".into(),
                        ));
                    }
                    env.forget_after_unverified(owner);
                    return false;
                };
                // A case expression may run before any selected body. Apply
                // unknown effects to every arm before analyzing their bodies.
                for case in cases {
                    if !matches!(kind(case), "SwitchCaseValues" | "SwitchCaseDefault") {
                        if self.strict(node) {
                            self.coverage.unverified_control_flow += 1;
                            self.findings.push(issue(
                                node,
                                "unverified-control-flow",
                                format!("unsupported switch case {}", kind(case)),
                            ));
                        }
                        env.forget_after_unverified(owner);
                        return false;
                    }
                    for choice in f(case, "Values").as_array().into_iter().flatten() {
                        self.inspect_expr(choice, owner, env);
                        env.invalidate_after_checked(choice, owner, self.symbols);
                        invalidate_result_after(choice, &mut env.result_fact);
                    }
                }
                let mut continuing = Vec::new();
                let mut has_default = false;
                for case in cases {
                    has_default |= kind(case) == "SwitchCaseDefault";
                    let mut arm = env.clone();
                    if !self.block(f(case, "Body"), owner, sig, &mut arm) {
                        continuing.push(arm);
                    }
                }
                if !has_default {
                    continuing.push(env.clone());
                }
                if continuing.is_empty() {
                    return true;
                }
                let mut merged = continuing.remove(0);
                for arm in continuing {
                    merged.slots = join_env(&merged.slots, &arm.slots, self.symbols);
                    merged.facts = join_env(&merged.facts, &arm.facts, self.symbols);
                    merged.assigned = merged
                        .assigned
                        .intersection(&arm.assigned)
                        .cloned()
                        .collect();
                    merged.fresh_collections = merged
                        .fresh_collections
                        .intersection(&arm.fresh_collections)
                        .cloned()
                        .collect();
                    merged.result_fact = merged.result_fact.join(&arm.result_fact, self.symbols);
                }
                *env = merged;
                false
            }
            "DMASTProcStatementFor" | "DMASTProcStatementWhile" | "DMASTProcStatementDoWhile" => {
                let mut body = env.clone();
                let mut loop_local = None;
                let iterator = f(node, "Expression1");
                let condition = f(node, "Conditional");
                if kind(node) == "DMASTProcStatementWhile" && !condition.is_null() {
                    self.inspect_condition(condition, owner, env);
                    env.invalidate_after_checked(condition, owner, self.symbols);
                    invalidate_result_after(condition, &mut env.result_fact);
                    body.invalidate_after(condition);
                    invalidate_result_after(condition, &mut body.result_fact);
                    if !contains_unknown_effect(condition) {
                        seed_guard_facts(condition, &mut body.facts, self, owner);
                        narrow_env(condition, true, &mut body);
                    }
                }
                if kind(iterator) == "DMASTExpressionIn" {
                    let collection_expr = f(iterator, "RHS");
                    self.inspect_expr(collection_expr, owner, env);
                    let collection = self.expression(collection_expr, &env.facts, owner);
                    if collection == Ty::Unknown && self.strict(node) {
                        self.findings.push(issue(
                            collection_expr,
                            "unverified-iterable",
                            "loop source has no proven iterable type".into(),
                        ));
                    }
                    env.invalidate_after_checked(collection_expr, owner, self.symbols);
                    invalidate_result_after(collection_expr, &mut env.result_fact);
                    body.invalidate_after(collection_expr);
                    invalidate_result_after(collection_expr, &mut body.result_fact);
                    let lhs = f(iterator, "LHS");
                    let new_local = iterator_declaration(lhs);
                    let binding = new_local.clone().or_else(|| {
                        let name = place(lhs)?;
                        Some((name.clone(), env.slots.get(&name)?.clone()))
                    });
                    if let Some((name, declared)) = binding {
                        // With no `as anything`, DM filters each iteration by
                        // the declared type before entering the loop body.
                        let runtime_filtered =
                            f(node, "DMTypes").is_null() && declared.is_precise();
                        let element = if runtime_filtered {
                            declared.clone()
                        } else {
                            match collection {
                                Ty::List(value) => *value,
                                Ty::Assoc(key, _) | Ty::Alist(key, _) => *key,
                                Ty::Record(_) => Ty::Text,
                                _ => Ty::Unknown,
                            }
                        };
                        if element == Ty::Unknown && self.strict(node) {
                            self.findings.push(issue(
                                iterator,
                                "unverified-iterator-element",
                                format!("{name} iterates over a collection without a proven element type"),
                            ));
                        }
                        if declared != Ty::Unknown && element != Ty::Unknown {
                            self.assignment(iterator, &declared, &element, &name);
                        }
                        body.slots.insert(
                            name.clone(),
                            if declared == Ty::Unknown {
                                element.clone()
                            } else {
                                declared
                            },
                        );
                        body.facts.insert(name.clone(), element);
                        body.assigned.insert(name.clone());
                        if new_local.is_some() {
                            loop_local = Some((
                                name.clone(),
                                env.slots.get(&name).cloned(),
                                env.facts.get(&name).cloned(),
                                env.assigned.contains(&name),
                            ));
                        }
                    }
                } else if kind(iterator) == "DMASTExpressionInRange" {
                    // OpenDream exports `for(var/i in low to high)` separately
                    // from collection iteration. Each entered iteration binds
                    // a number, even when the declaration has no type path.
                    for part in ["StartRange", "EndRange", "Step"] {
                        let bound = f(iterator, part);
                        if !bound.is_null() {
                            self.inspect_expr(bound, owner, env);
                            env.invalidate_after_checked(bound, owner, self.symbols);
                            invalidate_result_after(bound, &mut env.result_fact);
                            body.invalidate_after(bound);
                            invalidate_result_after(bound, &mut body.result_fact);
                        }
                    }
                    let lhs = f(iterator, "Value");
                    let new_local = iterator_declaration(lhs);
                    let binding = new_local.clone().or_else(|| {
                        let name = place(lhs)?;
                        Some((name.clone(), env.slots.get(&name)?.clone()))
                    });
                    if let Some((name, declared)) = binding {
                        if declared != Ty::Unknown {
                            self.assignment(iterator, &declared, &Ty::Num, &name);
                        }
                        body.slots.insert(name.clone(), Ty::Num);
                        body.facts.insert(name.clone(), Ty::Num);
                        body.assigned.insert(name.clone());
                        if new_local.is_some() {
                            loop_local = Some((
                                name.clone(),
                                env.slots.get(&name).cloned(),
                                env.facts.get(&name).cloned(),
                                env.assigned.contains(&name),
                            ));
                        }
                    }
                } else if kind(node) == "DMASTProcStatementFor" {
                    for header in ["Expression1", "Expression2", "Expression3"] {
                        let expression = f(node, header);
                        if !expression.is_null() {
                            self.inspect_expr(expression, owner, env);
                            env.invalidate_after_checked(expression, owner, self.symbols);
                            invalidate_result_after(expression, &mut env.result_fact);
                        }
                    }
                    if self.strict(node) {
                        self.coverage.unverified_control_flow += 1;
                        self.findings.push(issue(
                            node,
                            "unverified-control-flow",
                            "for-loop initializer, condition, and step are not fully modeled"
                                .into(),
                        ));
                    }
                    env.forget_after_unverified(owner);
                    body.forget_after_unverified(owner);
                }
                let mut invariant = body;
                let mut converged = false;
                for _ in 0..12 {
                    let trial =
                        self.preview_loop_block(f(node, "Body"), owner, sig, invariant.clone());
                    let mut feedback = merge_envs(
                        trial.next.into_iter().chain(trial.continues).collect(),
                        self.symbols,
                    );
                    let Some(state) = feedback.as_mut() else {
                        converged = true;
                        break;
                    };
                    if matches!(
                        kind(node),
                        "DMASTProcStatementWhile" | "DMASTProcStatementDoWhile"
                    ) && !condition.is_null()
                    {
                        state.invalidate_after(condition);
                        invalidate_result_after(condition, &mut state.result_fact);
                        if !contains_unknown_effect(condition) {
                            seed_guard_facts(condition, &mut state.facts, self, owner);
                            narrow_env(condition, true, state);
                        }
                    }
                    let joined = merge_envs(vec![invariant.clone(), state.clone()], self.symbols)
                        .expect("loop invariant state exists");
                    if joined == invariant {
                        converged = true;
                        break;
                    }
                    invariant = joined;
                }
                let body_entry_facts = invariant.facts.clone();
                let flow = self.loop_block(f(node, "Body"), owner, sig, invariant);
                let mut iteration = merge_envs(
                    flow.next.into_iter().chain(flow.continues).collect(),
                    self.symbols,
                );
                if kind(node) == "DMASTProcStatementWhile" && !condition.is_null() {
                    if let Some(state) = iteration.as_mut() {
                        if state.facts != body_entry_facts {
                            self.inspect_condition(condition, owner, state);
                            state.invalidate_after(condition);
                            invalidate_result_after(condition, &mut state.result_fact);
                        }
                    }
                }
                if kind(node) == "DMASTProcStatementDoWhile" && !condition.is_null() {
                    if let Some(state) = iteration.as_mut() {
                        self.inspect_condition(condition, owner, state);
                        state.invalidate_after(condition);
                        invalidate_result_after(condition, &mut state.result_fact);
                    }
                }
                let body = merge_envs(
                    iteration.into_iter().chain(flow.breaks).collect(),
                    self.symbols,
                )
                .unwrap_or_else(|| env.clone());
                if self.strict(node) {
                    for (local, before) in &env.slots {
                        if let Some(after) = body.slots.get(local) {
                            if before != after
                                && before.is_precise()
                                && after.is_precise()
                                && matches!(
                                    before.join(after, self.symbols),
                                    Ty::Unknown | Ty::OneOf(_)
                                )
                            {
                                self.findings.push(issue(
                                    node,
                                    "local-type-conflict",
                                    format!(
                                        "{local} changes from {} to {} in a loop",
                                        before.label(),
                                        after.label()
                                    ),
                                ));
                            }
                        }
                    }
                }
                env.slots = join_env(&env.slots, &body.slots, self.symbols);
                env.facts = join_env(&env.facts, &body.facts, self.symbols);
                env.assigned.retain(|name| body.assigned.contains(name));
                env.fresh_collections
                    .retain(|name| body.fresh_collections.contains(name));
                env.result_fact = env.result_fact.join(&body.result_fact, self.symbols);
                if !converged {
                    if self.strict(node) {
                        self.coverage.unverified_control_flow += 1;
                        self.findings.push(issue(
                            node,
                            "unverified-loop-fixed-point",
                            "loop type state did not converge within 12 iterations".into(),
                        ));
                    }
                    env.forget_after_unverified(owner);
                }
                if let Some((name, slot, fact, assigned)) = loop_local {
                    if let Some(slot) = slot {
                        env.slots.insert(name.clone(), slot);
                    } else {
                        env.slots.remove(&name);
                    }
                    if let Some(fact) = fact {
                        env.facts.insert(name.clone(), fact);
                    } else {
                        env.facts.remove(&name);
                    }
                    if assigned {
                        env.assigned.insert(name);
                    } else {
                        env.assigned.remove(&name);
                    }
                }
                false
            }
            "DMASTProcStatementSet" => {
                self.inspect_expr(node, owner, env);
                env.invalidate_after_checked(node, owner, self.symbols);
                invalidate_result_after(node, &mut env.result_fact);
                false
            }
            _ => {
                if self.strict(node) {
                    self.coverage.unverified_control_flow += 1;
                    self.findings.push(issue(
                        node,
                        "unverified-control-flow",
                        format!("{} is not modeled by strict flow analysis", kind(node)),
                    ));
                }
                // Break/continue and other unsupported statements can change
                // reachable state. Preserve declared slot constraints,
                // but discard all value and liveness proofs after this point.
                env.forget_after_unverified(owner);
                false
            }
        }
    }

    fn block(&mut self, block: &Value, owner: &str, sig: &Signature, env: &mut Env) -> bool {
        let Some(statements) = f(block, "Statements").as_array() else {
            return false;
        };
        for statement in statements {
            if self.statement(statement, owner, sig, env) {
                return true;
            }
        }
        false
    }

    fn check_proc(&mut self, item: &Value) {
        let owner = item["owner"].as_str().unwrap_or("");
        let name = item["name"].as_str().unwrap_or("");
        if matches!(name, "Destroy" | "Del") {
            return;
        }
        let key = (owner.into(), name.into());
        let index = self.checked_versions.entry(key.clone()).or_default();
        let version = *index;
        *index += 1;
        let Some(versions) = self.proc_versions.get(&key) else {
            return;
        };
        let Some(sig) = versions.get(version).cloned() else {
            return;
        };
        // The body may have a proved own result that is safe for `..()` while
        // the effective virtual result remains unknown because an override is
        // incompatible. Report that open-call uncertainty on the final version.
        let return_type_checked = if version + 1 == versions.len() {
            self.procs
                .get(&key)
                .is_some_and(|effective| effective.result.is_precise())
        } else {
            sig.result.is_precise()
        };
        let origin = source(item);
        if sig.path != origin.0 || sig.line != origin.1 {
            self.findings.push(issue(
                item,
                "unresolved-proc-version",
                format!("{owner}/{name} definition order differs between AST passes"),
            ));
            return;
        }
        self.current_proc = Some(name.into());
        self.current_proc_version = Some(version);
        self.inferred_locals = self.infer_local_storage(&item["body"], owner, &sig);
        if self.strict(item) {
            let mut local_contracts = self
                .contracts
                .iter()
                .filter(|contract| {
                    contract.owner == owner
                        && contract.member == name
                        && contract.visibility == Visibility::LocalType
                })
                .peekable();
            if local_contracts.peek().is_some() {
                let mut local_names = HashSet::new();
                collect_local_names(&item["body"], &mut local_names);
                for contract in local_contracts {
                    if let Some(local) = contract.parameter.as_deref() {
                        if !local_names.contains(local) {
                            self.findings.push(issue(
                                item,
                                "missing-local-type-target",
                                format!("{owner}/{name} has no local variable named {local}"),
                            ));
                        }
                    }
                }
            }
        }
        let mut env = Env::default();
        env.facts.insert("src".into(), Ty::Path(owner.into()));
        for (index, param) in sig.parameters.iter().enumerate() {
            env.origins.insert(param.name.clone(), origin.clone());
            env.slots.insert(param.name.clone(), param.ty.clone());
            // DM arguments can be omitted or explicitly supplied as null.
            // A declared storage type constrains checked callers, but does not
            // establish a non-null fact at an externally callable entry point.
            env.facts
                .insert(param.name.clone(), with_nullable(param.ty.clone(), true));
            env.assigned.insert(param.name.clone());
            if self.strict(item) {
                self.coverage.strict_declarations += 1;
                if param.inferred_from_calls {
                    self.coverage.unresolved_declarations += 1;
                    let calls = self
                        .param_evidence
                        .get(&(owner.into(), name.into(), index))
                        .map_or(0, |evidence| evidence.calls);
                    let constraints = self
                        .param_evidence
                        .get(&(owner.into(), name.into(), index))
                        .map_or(0, |evidence| evidence.constraint_sites);
                    let mut parts = Vec::new();
                    if param.has_default && param.default_ty.is_precise() {
                        parts.push("a typed default".to_owned());
                    }
                    if constraints > 0 {
                        parts.push(format!("{constraints} numeric uses"));
                    }
                    if calls > 0 {
                        parts.push(format!("{calls} static calls"));
                    }
                    let basis = if parts.is_empty() {
                        "an inferred parent signature".to_owned()
                    } else {
                        parts.join(" and ")
                    };
                    self.findings.push(issue(
                        item,
                        "unverified-inferred-parameter",
                        format!(
                            "{owner}/{name}: {} is inferred as {} from {basis}, but dynamic or external callers remain unproved",
                            param.name,
                            param.ty.label()
                        ),
                    ));
                } else if !param.ty.is_precise() {
                    self.coverage.unresolved_declarations += 1;
                    let observed = self
                        .param_evidence
                        .get(&(owner.into(), name.into(), index))
                        .map(|evidence| {
                            if evidence.conflict {
                                format!(
                                    "; observed incompatible call-site types across {} calls",
                                    evidence.calls
                                )
                            } else if evidence.ty.is_precise() {
                                format!(
                                    "; observed {} at {} call sites ({} unresolved)",
                                    evidence.ty.label(),
                                    evidence.calls,
                                    evidence.unresolved
                                )
                            } else {
                                format!(
                                    "; {} call sites found, {} unresolved",
                                    evidence.calls, evidence.unresolved
                                )
                            }
                        })
                        .unwrap_or_default();
                    self.findings.push(issue(
                        item,
                        "unknown-parameter-type",
                        format!(
                            "{owner}/{name}: {} needs a type contract{observed}",
                            param.name
                        ),
                    ));
                } else {
                    self.coverage.known_declarations += 1;
                }
            }
        }
        if let Some(parameters) = item["parameters"].as_array() {
            for (parameter, spec) in parameters.iter().zip(&sig.parameters) {
                let default = &parameter["defaultValue"];
                if !default.is_null() {
                    let actual = self.expression(default, &env.facts, owner);
                    self.assignment(
                        item,
                        &spec.ty,
                        &actual,
                        &format!("default for {}", spec.name),
                    );
                }
            }
        }
        if self.strict(item) {
            self.coverage.strict_declarations += 1;
            if !return_type_checked {
                self.coverage.unresolved_declarations += 1;
                self.findings.push(issue(
                    item,
                    "unknown-return-type",
                    format!("{owner}/{name} has no checked return type"),
                ));
            } else if sig.inferred_nullable_result {
                self.coverage.unresolved_declarations += 1;
                self.findings.push(issue(
                    item,
                    "unannotated-nullable-return",
                    format!(
                        "{owner}/{name} returns {} on some paths and null on others; declare the nullable return contract",
                        sig.result.nonnull().label()
                    ),
                ));
            } else {
                self.coverage.known_declarations += 1;
            }
        }
        if sig.result_required
            && self
                .prove_record_builder(&item["body"], &sig)
                .is_some_and(|proved| proved == sig.result)
        {
            self.coverage.checked_assignments += 1;
            self.current_proc = None;
            self.current_proc_version = None;
            self.inferred_locals.clear();
            return;
        }
        let exits = self.block(&item["body"], owner, &sig, &mut env);
        if sig.result_required && sig.result != Ty::Void && !exits {
            self.assignment(item, &sig.result, &env.result_fact, "fallthrough return");
        }
        self.current_proc = None;
        self.current_proc_version = None;
        self.inferred_locals.clear();
    }
}

fn join_env(
    a: &HashMap<String, Ty>,
    b: &HashMap<String, Ty>,
    symbols: &Symbols,
) -> HashMap<String, Ty> {
    let mut joined = HashMap::new();
    for (name, ty) in a {
        joined.insert(
            name.clone(),
            b.get(name)
                .map(|other| ty.join(other, symbols))
                .unwrap_or(Ty::Unknown),
        );
    }
    joined
}

fn merge_envs(states: Vec<Env>, symbols: &Symbols) -> Option<Env> {
    let mut states = states.into_iter();
    let mut merged = states.next()?;
    for state in states {
        merged.slots = join_env(&merged.slots, &state.slots, symbols);
        merged.facts = join_env(&merged.facts, &state.facts, symbols);
        merged
            .origins
            .retain(|name, origin| state.origins.get(name) == Some(origin));
        merged.assigned = merged
            .assigned
            .intersection(&state.assigned)
            .cloned()
            .collect();
        merged.fresh_collections = merged
            .fresh_collections
            .intersection(&state.fresh_collections)
            .cloned()
            .collect();
        merged.result_fact = merged.result_fact.join(&state.result_fact, symbols);
    }
    Some(merged)
}

fn mentions_identifier(node: &Value, name: &str) -> bool {
    if kind(node) == "DMASTIdentifier" && f(node, "Identifier").as_str() == Some(name) {
        return true;
    }
    node.get("fields")
        .and_then(Value::as_object)
        .is_some_and(|fields| {
            fields.values().any(|value| {
                mentions_identifier(value, name)
                    || value.as_array().is_some_and(|items| {
                        items.iter().any(|item| mentions_identifier(item, name))
                    })
            })
        })
}

fn fresh_reaches_unknown_effect(node: &Value, name: &str) -> bool {
    let effect_root = matches!(
        kind(node),
        "DMASTCall"
            | "DMASTNewPath"
            | "DMASTNewExpr"
            | "DMASTNewInferred"
            | "DMASTAppend"
            | "DMASTProcCall"
    ) || (kind(node) == "DMASTDereference"
        && f(node, "Operations").as_array().is_some_and(|operations| {
            operations
                .iter()
                .any(|operation| kind(operation) == "CallOperation")
        }));
    if effect_root && contains_unknown_effect(node) && mentions_identifier(node, name) {
        return true;
    }
    node.get("fields")
        .and_then(Value::as_object)
        .is_some_and(|fields| {
            fields.values().any(|value| {
                fresh_reaches_unknown_effect(value, name)
                    || value.as_array().is_some_and(|items| {
                        items
                            .iter()
                            .any(|item| fresh_reaches_unknown_effect(item, name))
                    })
            })
        })
}

fn invalidate_after_preserving_fresh(
    expr: &Value,
    vars: &mut HashMap<String, Ty>,
    fresh: &mut HashSet<String>,
) {
    if !contains_unknown_effect(expr) {
        return;
    }
    let preserved: Vec<_> = fresh
        .iter()
        .filter(|name| !fresh_reaches_unknown_effect(expr, name))
        .filter_map(|name| vars.get(name).cloned().map(|ty| (name.clone(), ty)))
        .collect();
    invalidate_after(expr, vars);
    fresh.retain(|name| preserved.iter().any(|(key, _)| key == name));
    for (name, ty) in preserved {
        vars.insert(name, ty);
    }
}

fn join_return(a: Option<Ty>, b: Option<Ty>, symbols: &Symbols) -> Option<Ty> {
    match (a, b) {
        (Some(left), Some(right)) => Some(join_value_flow(&left, &right, symbols)),
        (Some(value), None) | (None, Some(value)) => Some(value),
        (None, None) => None,
    }
}

// Return values and untyped scalar field evidence can preserve this small
// dynamic union. Storage compatibility still uses Ty::join and rejects it.
fn join_value_flow(left: &Ty, right: &Ty, symbols: &Symbols) -> Ty {
    let nullable = left.may_be_null() || right.may_be_null();
    let mut left = left;
    let mut right = right;
    while let Ty::Nullable(inner) = left {
        left = inner;
    }
    while let Ty::Nullable(inner) = right {
        right = inner;
    }
    let joined = match (left, right) {
        (Ty::Num, Ty::Text) | (Ty::Text, Ty::Num) => Ty::OneOf(vec![Ty::Num, Ty::Text]),
        (Ty::OneOf(choices), value) | (value, Ty::OneOf(choices))
            if choices == &[Ty::Num, Ty::Text] && choices.contains(value) =>
        {
            Ty::OneOf(choices.clone())
        }
        _ => left.join(right, symbols),
    };
    with_nullable(joined, nullable)
}

fn known_pure_proc_call(node: &Value) -> bool {
    let name = f(f(node, "Callable"), "Identifier").as_str().unwrap_or("");
    if matches!(
        name,
        "isnull"
            | "QDELETED"
            | "islist"
            | "isnum"
            | "istext"
            | "isarea"
            | "ismob"
            | "isobj"
            | "isturf"
            | "ismovable"
    ) && !checked_unary_builtin(node)
    {
        return false;
    }
    if name == "ispath" && !checked_ispath_builtin(node) {
        return false;
    }
    if name == "text2path" && !checked_unary_builtin(node) {
        return false;
    }
    [
        "isnull",
        "istype",
        "ispath",
        "islist",
        "isnum",
        "istext",
        "isarea",
        "ismob",
        "isobj",
        "isturf",
        "ismovable",
        "text2path",
        "QDELETED",
        "length",
        "min",
        "max",
        "round",
        "lowertext",
        "view",
        "oview",
        "range",
        "orange",
        "viewers",
        "oviewers",
        "hearers",
        "ohearers",
    ]
    .contains(&name)
}

fn contains_unknown_effect(node: &Value) -> bool {
    match kind(node) {
        "DMASTCall" | "DMASTNewPath" | "DMASTNewExpr" | "DMASTNewInferred" | "DMASTAppend" => {
            return true
        }
        "DMASTProcCall" => {
            if !known_pure_proc_call(node) {
                return true;
            }
        }
        "DMASTDereference"
            if f(node, "Operations")
                .as_array()
                .is_some_and(|ops| ops.iter().any(|op| kind(op) == "CallOperation")) =>
        {
            return true;
        }
        _ => {}
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|child| {
            if let Some(items) = child.as_array() {
                items.iter().any(contains_unknown_effect)
            } else if child.is_object() {
                contains_unknown_effect(child)
            } else {
                false
            }
        })
    })
}

#[cfg(test)]
fn contains_unproved_effect(node: &Value, owner: &str, symbols: &Symbols) -> bool {
    contains_unproved_effect_with_vars(node, owner, symbols, &HashMap::new())
}

fn contains_unproved_effect_with_vars(
    node: &Value,
    owner: &str,
    symbols: &Symbols,
    vars: &HashMap<String, Ty>,
) -> bool {
    match kind(node) {
        "DMASTProcCall" => {
            let callable = f(node, "Callable");
            let name = f(callable, "Identifier").as_str().unwrap_or("");
            if !known_pure_proc_call(node)
                && (kind(callable) != "DMASTCallableProcIdentifier"
                    || !symbols.effect_free_global_call(owner, name))
            {
                return true;
            }
        }
        "DMASTCall" | "DMASTNewPath" | "DMASTNewExpr" | "DMASTNewInferred" | "DMASTAppend" => {
            return true
        }
        "DMASTDereference"
            if f(node, "Operations")
                .as_array()
                .is_some_and(|ops| ops.iter().any(|op| kind(op) == "CallOperation")) =>
        {
            let base = f(node, "Expression");
            let Some(operations) = f(node, "Operations").as_array() else {
                return true;
            };
            if operations.len() != 1 || kind(&operations[0]) != "CallOperation" {
                return true;
            }
            let method = f(&operations[0], "Identifier").as_str().unwrap_or("");
            if kind(base) == "DMASTNewPath" {
                let path = f(f(f(base, "Path"), "Value"), "Path")
                    .as_str()
                    .unwrap_or("");
                if !symbols.fresh_constructor_preserves_existing(path)
                    || !symbols.fresh_method_preserves_existing(path, method)
                {
                    return true;
                }
                return [f(base, "Parameters"), f(&operations[0], "Parameters")]
                    .into_iter()
                    .any(|parameters| {
                        parameters.as_array().is_none_or(|parameters| {
                            parameters.iter().any(|parameter| {
                                contains_unproved_effect_with_vars(parameter, owner, symbols, vars)
                            })
                        })
                    });
            }
            let receiver = if kind(base) == "DMASTIdentifier" {
                f(base, "Identifier")
                    .as_str()
                    .and_then(|name| vars.get(name))
            } else {
                None
            };
            let proven = match receiver {
                Some(Ty::Path(path)) => symbols.effect_free_dispatch(path, method),
                Some(Ty::Nullable(inner)) => match inner.as_ref() {
                    Ty::Path(path) => symbols.effect_free_dispatch(path, method),
                    _ => false,
                },
                _ => false,
            };
            if !proven {
                return true;
            }
            return f(&operations[0], "Parameters")
                .as_array()
                .is_none_or(|parameters| {
                    parameters.iter().any(|parameter| {
                        contains_unproved_effect_with_vars(parameter, owner, symbols, vars)
                    })
                });
        }
        _ => {}
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|child| {
            if let Some(items) = child.as_array() {
                items
                    .iter()
                    .any(|item| contains_unproved_effect_with_vars(item, owner, symbols, vars))
            } else if child.is_object() {
                contains_unproved_effect_with_vars(child, owner, symbols, vars)
            } else {
                false
            }
        })
    })
}

fn has_explicit_value_return(node: &Value) -> bool {
    // A spawned block runs after the caller has returned. Its `return`
    // belongs to that block and cannot establish the enclosing proc result.
    if kind(node) == "DMASTProcStatementSpawn" {
        return false;
    }
    if kind(node) == "DMASTProcStatementReturn" && !f(node, "Value").is_null() {
        return true;
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|child| {
            if let Some(items) = child.as_array() {
                items.iter().any(has_explicit_value_return)
            } else if child.is_object() {
                has_explicit_value_return(child)
            } else {
                false
            }
        })
    })
}

fn has_implicit_result_assignment(node: &Value) -> bool {
    if kind(node) == "DMASTProcStatementSpawn" {
        return false;
    }
    if kind(node) == "DMASTAssign" && kind(f(node, "LHS")) == "DMASTCallableSelf" {
        return true;
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|child| {
            if let Some(items) = child.as_array() {
                items.iter().any(has_implicit_result_assignment)
            } else if child.is_object() {
                has_implicit_result_assignment(child)
            } else {
                false
            }
        })
    })
}

fn references_implicit_result(node: &Value) -> bool {
    if kind(node) == "DMASTCallableSelf" {
        return true;
    }
    node["fields"].as_object().is_some_and(|fields| {
        fields.values().any(|child| {
            if let Some(items) = child.as_array() {
                items.iter().any(references_implicit_result)
            } else if child.is_object() {
                references_implicit_result(child)
            } else {
                false
            }
        })
    })
}

fn checked_unary_builtin(expr: &Value) -> bool {
    f(expr, "Parameters")
        .as_array()
        .is_some_and(|args| args.len() == 1 && f(&args[0], "Key").is_null())
}

fn checked_ispath_builtin(expr: &Value) -> bool {
    let Some(args) = f(expr, "Parameters").as_array() else {
        return false;
    };
    if !(1..=2).contains(&args.len()) || args.iter().any(|arg| !f(arg, "Key").is_null()) {
        return false;
    }
    args.len() == 1 || kind(f(&args[1], "Value")) == "DMASTConstantPath"
}

fn empty_list_literal(expr: &Value) -> bool {
    let expr = if kind(expr) == "DMASTExpressionWrapped" {
        f(expr, "Value")
    } else {
        expr
    };
    match kind(expr) {
        "DMASTList" => {
            f(expr, "IsAList").as_bool() != Some(true)
                && f(expr, "Values").as_array().is_some_and(Vec::is_empty)
        }
        "DMASTNewList" => f(expr, "Parameters").as_array().is_some_and(Vec::is_empty),
        _ => false,
    }
}

fn contextual_empty_list(actual: Ty, expected: &Ty) -> Ty {
    // An unparameterized `var/list` declares storage but gives no element
    // evidence. Keep a freshly constructed empty list empty so a later
    // checked indexed write can establish its first element shape.
    if matches!(actual, Ty::EmptyList | Ty::EmptyAlist) && expected.has_unknown() {
        return actual;
    }
    let nonnull = expected.nonnull();
    let accepts_empty_record =
        matches!(&nonnull, Ty::Record(fields) if fields.values().all(|(_, optional)| *optional));
    if (actual == Ty::EmptyList
        && (matches!(nonnull, Ty::List(_) | Ty::Assoc(_, _)) || accepts_empty_record))
        || (actual == Ty::EmptyAlist && matches!(nonnull, Ty::Alist(_, _)))
    {
        nonnull
    } else {
        actual
    }
}

fn invalidate_after(expr: &Value, vars: &mut HashMap<String, Ty>) {
    if !contains_unknown_effect(expr) {
        return;
    }
    vars.retain(|key, _| !key.contains('.'));
    for fact in vars.values_mut() {
        *fact = stale_after_unknown_effect(fact);
    }
    vars.insert(STALE_REFERENCES.into(), Ty::Num);
}

fn invalidate_result_after(expr: &Value, result: &mut Ty) {
    if contains_unknown_effect(expr) {
        *result = stale_after_unknown_effect(result);
    }
}

fn stale_after_unknown_effect(ty: &Ty) -> Ty {
    match ty {
        Ty::NonNullUnknown => Ty::Unknown,
        Ty::EmptyList
        | Ty::EmptyAlist
        | Ty::List(_)
        | Ty::Assoc(_, _)
        | Ty::Alist(_, _)
        | Ty::Record(_)
        | Ty::OneOf(_) => Ty::Unknown,
        Ty::Nullable(inner) => match stale_after_unknown_effect(inner) {
            Ty::Unknown => Ty::Unknown,
            other => Ty::Nullable(Box::new(other.nonnull())),
        },
        Ty::Path(_) => Ty::Nullable(Box::new(ty.clone())),
        _ => ty.clone(),
    }
}

fn stale_field_after_unknown_effect(ty: &Ty) -> Ty {
    match ty {
        Ty::Unknown
        | Ty::NonNullUnknown
        | Ty::Null
        | Ty::EmptyList
        | Ty::EmptyAlist
        | Ty::List(_)
        | Ty::Assoc(_, _)
        | Ty::Alist(_, _)
        | Ty::Record(_)
        | Ty::OneOf(_) => Ty::Unknown,
        Ty::Nullable(_) => stale_after_unknown_effect(ty),
        Ty::Void => Ty::Unknown,
        other => Ty::Nullable(Box::new(other.clone())),
    }
}

fn narrow_env(condition: &Value, truth: bool, env: &mut Env) {
    narrow(condition, truth, &mut env.facts);
    narrow_implicit_type(condition, truth, &env.slots, &mut env.facts);
}

fn narrow_implicit_type(
    condition: &Value,
    truth: bool,
    slots: &HashMap<String, Ty>,
    facts: &mut HashMap<String, Ty>,
) {
    match kind(condition) {
        "DMASTImplicitIsType" if truth => {
            if let Some(name) = place(f(condition, "Value")) {
                if let Some(Ty::Path(path)) = slots.get(&name).map(Ty::nonnull) {
                    facts.insert(name, Ty::Path(path));
                }
            }
        }
        "DMASTNot" => narrow_implicit_type(f(condition, "Value"), !truth, slots, facts),
        "DMASTAnd" if truth => {
            narrow_implicit_type(f(condition, "LHS"), true, slots, facts);
            if contains_unknown_effect(f(condition, "RHS")) {
                invalidate_after(f(condition, "RHS"), facts);
            }
            narrow_implicit_type(f(condition, "RHS"), true, slots, facts);
        }
        "DMASTOr" if !truth => {
            narrow_implicit_type(f(condition, "LHS"), false, slots, facts);
            if contains_unknown_effect(f(condition, "RHS")) {
                invalidate_after(f(condition, "RHS"), facts);
            }
            narrow_implicit_type(f(condition, "RHS"), false, slots, facts);
        }
        _ => {}
    }
}

fn narrow(condition: &Value, truth: bool, vars: &mut HashMap<String, Ty>) {
    match kind(condition) {
        "DMASTIsNull" => {
            let value = f(condition, "Value");
            if let Some(key) = place(value) {
                if let Some(ty) = vars.get_mut(&key) {
                    *ty = if truth { Ty::Null } else { ty.nonnull() };
                }
            }
        }
        "DMASTIsType" if truth => {
            let value = f(condition, "LHS");
            let target = f(condition, "RHS");
            if kind(target) == "DMASTConstantPath" {
                if let (Some(name), Some(path)) =
                    (place(value), f(f(target, "Value"), "Path").as_str())
                {
                    if let Some(ty) = vars.get_mut(&name) {
                        *ty = Ty::parse(path);
                    }
                }
            }
        }
        "DMASTImplicitIsType" if truth => {
            let value = f(condition, "Value");
            if let Some(key) = place(value) {
                if let Some(ty) = vars.get_mut(&key) {
                    *ty = ty.nonnull();
                }
            }
        }
        "DMASTNot" => narrow(f(condition, "Value"), !truth, vars),
        "DMASTAnd" if truth => {
            narrow(f(condition, "LHS"), true, vars);
            invalidate_after(f(condition, "RHS"), vars);
            narrow(f(condition, "RHS"), true, vars);
        }
        "DMASTOr" if !truth => {
            narrow(f(condition, "LHS"), false, vars);
            invalidate_after(f(condition, "RHS"), vars);
            narrow(f(condition, "RHS"), false, vars);
        }
        "DMASTEqual" | "DMASTNotEqual" => {
            let lhs = f(condition, "LHS");
            let rhs = f(condition, "RHS");
            let candidate = if kind(lhs) == "DMASTConstantNull" {
                rhs
            } else if kind(rhs) == "DMASTConstantNull" {
                lhs
            } else {
                return;
            };
            if let Some(name) = place(candidate) {
                if let Some(ty) = vars.get_mut(&name) {
                    let is_null = (kind(condition) == "DMASTEqual") == truth;
                    *ty = if is_null { Ty::Null } else { ty.nonnull() };
                }
            }
        }
        "DMASTIdentifier" | "DMASTDereference" if truth => {
            if let Some(name) = place(condition) {
                if let Some(ty) = vars.get_mut(&name) {
                    *ty = ty.nonnull();
                }
            }
        }
        "DMASTProcCall" => {
            let name = f(f(condition, "Callable"), "Identifier")
                .as_str()
                .unwrap_or("");
            if name == "ispath" {
                if truth && checked_ispath_builtin(condition) {
                    if let Some(arguments) = f(condition, "Parameters")
                        .as_array()
                        .filter(|args| args.len() == 2)
                    {
                        let bound = f(f(f(&arguments[1], "Value"), "Value"), "Path").as_str();
                        let key = place(f(&arguments[0], "Value"));
                        if let (Some(bound), Some(key)) = (bound, key) {
                            if let Some(ty) = vars.get_mut(&key) {
                                *ty = Ty::TypePath(bound.into());
                            }
                        }
                    }
                }
                return;
            }
            if matches!(name, "isnum" | "istext") {
                if truth && checked_unary_builtin(condition) {
                    if let Some(argument) = f(condition, "Parameters")
                        .as_array()
                        .and_then(|args| args.first())
                    {
                        if let Some(key) = place(f(argument, "Value")) {
                            if let Some(ty) = vars.get_mut(&key) {
                                *ty = if name == "isnum" { Ty::Num } else { Ty::Text };
                            }
                        }
                    }
                }
                return;
            }
            if name == "islist" {
                if truth && checked_unary_builtin(condition) {
                    let Some(argument) = f(condition, "Parameters")
                        .as_array()
                        .and_then(|args| args.first())
                    else {
                        return;
                    };
                    if let Some(place) = place(f(argument, "Value")) {
                        if let Some(ty) = vars.get_mut(&place) {
                            *ty = match ty.nonnull() {
                                Ty::List(_) | Ty::Assoc(_, _) | Ty::Alist(_, _) => ty.nonnull(),
                                _ => Ty::List(Box::new(Ty::Unknown)),
                            };
                        }
                    }
                }
                return;
            }
            let tested_path = match name {
                "isarea" => Some("/area"),
                "ismob" => Some("/mob"),
                "isobj" => Some("/obj"),
                "isturf" => Some("/turf"),
                "ismovable" => Some("/atom/movable"),
                _ => None,
            };
            if let Some(tested_path) = tested_path {
                if truth && checked_unary_builtin(condition) {
                    let value = f(condition, "Parameters")
                        .as_array()
                        .and_then(|args| args.first())
                        .map(|argument| f(argument, "Value"));
                    if let Some(key) = value.and_then(place) {
                        if let Some(ty) = vars.get_mut(&key) {
                            let existing = ty.nonnull();
                            *ty = match &existing {
                                Ty::Path(path)
                                    if path == tested_path
                                        || path.starts_with(&format!("{tested_path}/")) =>
                                {
                                    existing
                                }
                                _ => Ty::Path(tested_path.into()),
                            };
                        }
                    }
                }
                return;
            }
            if name != "isnull" && name != "QDELETED" {
                return;
            }
            let Some(argument) = f(condition, "Parameters")
                .as_array()
                .and_then(|args| args.first())
            else {
                return;
            };
            let candidate = f(argument, "Value");
            if let Some(place_name) = place(candidate) {
                if let Some(ty) = vars.get_mut(&place_name) {
                    if truth {
                        *ty = if name == "isnull" {
                            Ty::Null
                        } else {
                            Ty::Nullable(Box::new(ty.nonnull()))
                        };
                    } else {
                        *ty = ty.nonnull();
                    }
                }
            }
        }
        _ => {}
    }
}

fn read_item(line: &str) -> io::Result<Value> {
    let mut deserializer = serde_json::Deserializer::from_str(line);
    deserializer.disable_recursion_limit();
    Value::deserialize(&mut deserializer).map_err(io::Error::other)
}

fn prepare_call_evidence(checker: &mut Checker<'_>) {
    checker.param_evidence.clear();
    for ((owner, name), versions) in &checker.proc_versions {
        if let Some(last) = versions.last() {
            for (index, _) in last.parameters.iter().enumerate() {
                if versions.iter().any(|version| {
                    version
                        .parameters
                        .get(index)
                        .is_some_and(|param| param.has_default && param.default_ty.is_precise())
                }) {
                    checker.param_evidence.insert(
                        (owner.clone(), name.clone(), index),
                        ParamEvidence {
                            ty: Ty::Unknown,
                            calls: 0,
                            unresolved: 0,
                            conflict: false,
                            constraint: None,
                            constraint_sites: 0,
                        },
                    );
                }
            }
        }
    }
}

fn scan_call_evidence_item(checker: &mut Checker<'_>, item: &Value) {
    if matches!(item["kind"].as_str(), Some("field" | "field-override")) {
        let owner = item["owner"].as_str().unwrap_or("");
        let name = item["name"].as_str().unwrap_or("");
        let storage = checker
            .field_key(owner, name)
            .and_then(|key| checker.fields.get(&key))
            .map(|field| field.ty.clone())
            .unwrap_or(Ty::Unknown);
        checker.record_inferred_constructor(&item["initializer"], &storage, owner, &HashMap::new());
        checker.collect_call_evidence(&item["initializer"], owner, &HashMap::new());
        return;
    }
    if item["kind"] != "proc" || matches!(item["name"].as_str(), Some("Destroy" | "Del")) {
        return;
    }
    let owner = item["owner"].as_str().unwrap_or("");
    if owner == "/client" {
        if let Some(wrapper_name) = item["name"].as_str() {
            if let Some(target) = admin_verb_wrapper_target(wrapper_name, &item["body"]) {
                let wrapper_key = ("/client".to_owned(), wrapper_name.to_owned());
                let target_key = (target, "__avd_do_verb".to_owned());
                if let (Some(wrapper), Some(target)) = (
                    checker.procs.get(&wrapper_key).cloned(),
                    checker.procs.get(&target_key).cloned(),
                ) {
                    if target.parameters.len() == wrapper.parameters.len() + 1
                        && target
                            .parameters
                            .first()
                            .is_some_and(|parameter| parameter.ty == Ty::Path("/client".into()))
                    {
                        for (index, parameter) in wrapper.parameters.iter().enumerate() {
                            let implementation = &target.parameters[index + 1];
                            if implementation.ty.is_precise() {
                                checker.add_param_evidence(
                                    &wrapper_key,
                                    index,
                                    implementation.ty.clone(),
                                );
                            }
                            if parameter.ty.is_precise() {
                                checker.add_param_evidence(
                                    &target_key,
                                    index + 1,
                                    parameter.ty.clone(),
                                );
                            }
                        }
                    }
                }
            }
        }
    }
    checker.current_proc = item["name"].as_str().map(str::to_owned);
    let sig = checker
        .procs
        .get(&(owner.into(), item["name"].as_str().unwrap_or("").into()))
        .cloned();
    let mut vars: HashMap<String, Ty> = sig
        .into_iter()
        .flat_map(|sig| {
            sig.parameters
                .into_iter()
                .map(|param| (param.name, with_nullable(param.ty, true)))
        })
        .collect();
    vars.insert("src".into(), Ty::Path(owner.into()));
    checker.scan_call_block(&item["body"], owner, &mut vars);
    checker.record_parameter_constraints(&item["body"], owner, item["name"].as_str().unwrap_or(""));
}

type FieldSeed = HashMap<(String, String), (Ty, bool, bool)>;

// The outer inference pass can replace a field hypothesis after rescanning
// writes. Keep an exact state so a cycle cannot masquerade as progress.
fn inference_state(checker: &Checker<'_>) -> Vec<(String, Ty)> {
    let mut state = Vec::new();
    for ((owner, name), field) in &checker.fields {
        state.push((format!("field:{owner}:{name}"), field.ty.clone()));
    }
    for ((owner, name), versions) in &checker.proc_versions {
        for (version, signature) in versions.iter().enumerate() {
            state.push((
                format!("return:{owner}:{name}:{version}"),
                signature.result.clone(),
            ));
            for (index, parameter) in signature.parameters.iter().enumerate() {
                state.push((
                    format!("parameter:{owner}:{name}:{version}:{index}"),
                    parameter.ty.clone(),
                ));
            }
        }
    }
    for ((owner, name), signature) in &checker.procs {
        state.push((format!("dispatch:{owner}:{name}"), signature.result.clone()));
    }
    state.sort_unstable_by(|a, b| a.0.cmp(&b.0));
    state
}

fn widen_oscillating_fields(
    fields: &mut HashMap<(String, String), FieldInfo>,
    before: &HashMap<(String, String), Ty>,
    prior: Option<&HashMap<(String, String), Ty>>,
    locked: &mut HashSet<(String, String)>,
) -> Vec<Finding> {
    let mut findings = Vec::new();
    for (key, field) in fields {
        let oscillates = prior
            .and_then(|types| types.get(key))
            .is_some_and(|previous| previous == &field.ty && before.get(key) != Some(&field.ty));
        if oscillates && locked.insert(key.clone()) {
            let mut finding = issue(
                &field.origin,
                "cyclic-field-inference",
                format!(
                    "{}.{} changes type on alternating inference passes; its type remains unknown",
                    key.0, key.1
                ),
            );
            finding.severity = "warning";
            findings.push(finding);
        }
        if locked.contains(key) {
            field.ty = Ty::Unknown;
            field.evidence = Ty::Unknown;
        }
    }
    findings
}

fn refresh_evidence<S: BufRead + Seek>(
    checker: &mut Checker<'_>,
    source: &mut S,
    seeds: &FieldSeed,
) -> io::Result<()> {
    for (key, (evidence, unknown_write, conflict)) in seeds {
        if let Some(field) = checker.fields.get_mut(key) {
            field.evidence = evidence.clone();
            field.saw_unknown_write = *unknown_write;
            field.conflict = *conflict;
        }
    }
    prepare_call_evidence(checker);
    source.seek(SeekFrom::Start(0))?;
    for line in source.lines() {
        let item = read_item(&line?)?;
        if item["kind"] == "proc" && !matches!(item["name"].as_str(), Some("Destroy" | "Del")) {
            let owner = item["owner"].as_str().unwrap_or("");
            let sig = checker
                .procs
                .get(&(owner.into(), item["name"].as_str().unwrap_or("").into()))
                .cloned();
            let mut vars: HashMap<String, Ty> = sig
                .into_iter()
                .flat_map(|sig| {
                    sig.parameters
                        .into_iter()
                        .map(|param| (param.name, with_nullable(param.ty, true)))
                })
                .collect();
            vars.insert("src".into(), Ty::Path(owner.into()));
            let mut locals: HashSet<String> = vars.keys().cloned().collect();
            collect_local_names(&item["body"], &mut locals);
            if std::env::var_os("DM_HEALTH_PROFILE").is_some() {
                PROFILE_WRITE_PROC.with(|name| {
                    *name.borrow_mut() = item["name"].as_str().map(str::to_owned);
                });
            }
            checker.register_writes(&item["body"], owner, &vars, &locals);
            if std::env::var_os("DM_HEALTH_PROFILE").is_some() {
                PROFILE_WRITE_PROC.with(|name| *name.borrow_mut() = None);
            }
        }
        scan_call_evidence_item(checker, &item);
    }
    checker.current_proc = None;
    Ok(())
}

pub fn analyze<R: BufRead, S: BufRead, T: BufRead>(
    first: R,
    mut second: S,
    third: T,
    symbols: &Symbols,
    contracts: &[Contract],
    selection: &Selection,
) -> io::Result<(Vec<Finding>, TypeCoverage)> {
    let mut bytes = Vec::new();
    second.read_to_end(&mut bytes)?;
    analyze_with_cache(
        first,
        Cursor::new(bytes),
        third,
        symbols,
        contracts,
        selection,
        None,
    )
}

pub fn analyze_with_cache<R: BufRead, S: BufRead + Seek, T: BufRead>(
    first: R,
    mut second: S,
    third: T,
    symbols: &Symbols,
    contracts: &[Contract],
    selection: &Selection,
    cache_directory: Option<&Path>,
) -> io::Result<(Vec<Finding>, TypeCoverage)> {
    let profile = std::env::var_os("DM_HEALTH_PROFILE").is_some();
    let started = Instant::now();
    let mut evidence_time = Duration::ZERO;
    let mut parameter_time = Duration::ZERO;
    let mut return_time = Duration::ZERO;
    let mut evidence_passes = 0usize;
    let mut checker = Checker {
        symbols,
        contracts,
        selection,
        fields: HashMap::new(),
        overrides: Vec::new(),
        procs: HashMap::new(),
        proc_versions: HashMap::new(),
        checked_versions: HashMap::new(),
        param_evidence: HashMap::new(),
        return_bodies: HashMap::new(),
        new_bodies: HashMap::new(),
        current_proc: None,
        current_proc_version: None,
        inferred_locals: HashMap::new(),
        findings: Vec::new(),
        coverage: TypeCoverage::default(),
    };
    checker.coverage.bridge_schema = symbols.bridge_schema;
    checker.coverage.frontend_errors = symbols.frontend_errors;
    checker.coverage.frontend_verified =
        symbols.bridge_schema >= 4 && symbols.frontend_errors == Some(0);
    if !checker.coverage.frontend_verified && (selection.all || !selection.modules.is_empty()) {
        checker.findings.push(Finding {
            rule: "unverified-ast-export",
            path: "<ast>".into(),
            line: 1,
            severity: "error",
            message: format!(
                "strict types require OpenDreamBridge schema 4 with zero frontend errors and verified source hashes (schema {}, errors {})",
                symbols.bridge_schema,
                symbols.frontend_errors.map_or("unknown".into(), |n| n.to_string())
            ),
        });
    }
    for (owner, path, line) in &symbols.unresolved_parents {
        if selection.includes(path) {
            checker.findings.push(Finding {
                rule: "unresolved-parent-type",
                path: path.clone(),
                line: *line,
                severity: "error",
                message: format!("{owner} has a parent_type that cannot be resolved"),
            });
        }
    }
    let mut structural = cache_directory.map(|_| Sha256::new());
    for line in first.lines() {
        let line = line?;
        let item = read_item(&line)?;
        if let Some(hash) = structural.as_mut() {
            let mut identity = item.clone();
            if item["kind"] == "bridge-meta" {
                identity
                    .as_object_mut()
                    .map(|meta| meta.remove("sourceFiles"));
            } else if item["kind"] == "proc" {
                identity["body"] = Value::Null;
            }
            hash_value(hash, &serde_json::to_vec(&identity)?);
        }
        checker.register(&item);
    }
    for (owner, name) in &symbols.duplicate_procs {
        if let Some(signature) = checker.procs.get(&(owner.clone(), name.clone())) {
            if selection.includes(&signature.path) {
                checker.findings.push(Finding {
                    rule: "duplicate-proc-definition",
                    path: signature.path.clone(),
                    line: signature.line,
                    severity: "error",
                    message: format!("{owner}/{name} has multiple definitions; parent dispatch and signatures need declaration order"),
                });
            }
        }
    }
    checker.apply_overrides();
    checker.inherit_override_parameter_types();
    let registration_time = started.elapsed();
    let field_seeds: FieldSeed = checker
        .fields
        .iter()
        .map(|(key, field)| {
            (
                key.clone(),
                (
                    field.evidence.clone(),
                    field.saw_unknown_write,
                    field.conflict,
                ),
            )
        })
        .collect();
    let phase = Instant::now();
    refresh_evidence(&mut checker, &mut second, &field_seeds)?;
    let initial_refresh_time = phase.elapsed();
    evidence_time += initial_refresh_time;
    evidence_passes += 1;
    let initial_field_started = Instant::now();
    let mut fields_changed = checker.infer_field_types();
    if profile {
        eprintln!("dm-health inference seed: registration={registration_time:?} initial_evidence={initial_refresh_time:?} initial_field_inference={:?}", initial_field_started.elapsed());
    }
    // Re-evaluate call arguments after newly inferred parameter types become
    // available to their callers. The stream is seekable, so this does not
    // retain the full OpenDream AST in memory on large repositories.
    let mut inference_converged = false;
    let mut inference_cycle = false;
    let mut seen_inference_states = Vec::new();
    let mut prior_field_types: Option<HashMap<(String, String), Ty>> = None;
    let mut cyclic_fields = HashSet::new();
    for round in 0..8 {
        let state_started = Instant::now();
        let state_before = inference_state(&checker);
        if profile {
            eprintln!(
                "dm-health inference round {}: snapshot={:?} entries={}",
                round + 1,
                state_started.elapsed(),
                state_before.len()
            );
        }
        if seen_inference_states.contains(&state_before) {
            inference_cycle = true;
            checker.findings.push(Finding {
                rule: "parameter-inference-cycle",
                path: "<ast>".into(),
                line: 1,
                severity: "error",
                message: format!(
                    "parameter, return, and field inference repeated a prior state in round {}",
                    round + 1
                ),
            });
            break;
        }
        seen_inference_states.push(state_before);
        let phase = Instant::now();
        let direct_parameters_changed = checker.infer_parameters();
        let direct_parameter_time = phase.elapsed();
        let inherited_parameters_changed = checker.inherit_override_parameter_types();
        let parameters_changed = direct_parameters_changed | inherited_parameters_changed;
        parameter_time += phase.elapsed();
        if profile {
            eprintln!(
                "dm-health inference round {}: direct_parameters={:?} inherited_parameters={:?}",
                round + 1,
                direct_parameter_time,
                phase.elapsed() - direct_parameter_time
            );
        }
        let return_snapshot_started = Instant::now();
        let returns_before: HashMap<_, _> = checker
            .procs
            .iter()
            .map(|(key, signature)| (key.clone(), signature.result.clone()))
            .collect();
        if profile {
            eprintln!(
                "dm-health inference round {}: return_snapshot={:?}",
                round + 1,
                return_snapshot_started.elapsed()
            );
        }
        let phase = Instant::now();
        if profile {
            eprintln!(
                "dm-health inference round {}: entering return inference",
                round + 1
            );
        }
        checker.infer_returns();
        return_time += phase.elapsed();
        let returns_changed = checker
            .procs
            .iter()
            .any(|(key, signature)| returns_before.get(key) != Some(&signature.result));
        if profile {
            let field_state = |owner: &str, name: &str| {
                checker
                    .fields
                    .get(&(owner.into(), name.into()))
                    .map(|field| {
                        format!(
                            "type:{} evidence:{} unknown_write:{} conflict:{}",
                            field.ty.label(),
                            field.evidence.label(),
                            field.saw_unknown_write,
                            field.conflict,
                        )
                    })
                    .unwrap_or_else(|| "<absent>".into())
            };
            eprintln!(
                "dm-health inference round {}: parameters_changed={} returns_changed={} fields_changed={} atom.desc={} simple_mob.icon_living={}",
                round + 1,
                parameters_changed,
                returns_changed,
                fields_changed,
                field_state("/atom", "desc"),
                field_state("/mob/living/simple_mob", "icon_living"),
            );
        }
        if !parameters_changed && !returns_changed && !fields_changed {
            inference_converged = true;
            break;
        }
        let field_types_before: HashMap<_, _> = checker
            .fields
            .iter()
            .map(|(key, field)| (key.clone(), field.ty.clone()))
            .collect();
        let phase = Instant::now();
        refresh_evidence(&mut checker, &mut second, &field_seeds)?;
        evidence_time += phase.elapsed();
        evidence_passes += 1;
        checker.infer_field_types();
        checker.findings.extend(widen_oscillating_fields(
            &mut checker.fields,
            &field_types_before,
            prior_field_types.as_ref(),
            &mut cyclic_fields,
        ));
        fields_changed = checker
            .fields
            .iter()
            .any(|(key, field)| field_types_before.get(key) != Some(&field.ty));
        prior_field_types = Some(field_types_before.clone());
        if profile {
            let mut changes: Vec<_> = checker
                .fields
                .iter()
                .filter_map(|(key, field)| {
                    let previous = field_types_before.get(key)?;
                    (previous != &field.ty).then(|| {
                        format!(
                            "{}.{}: {} -> {}",
                            key.0,
                            key.1,
                            previous.label(),
                            field.ty.label()
                        )
                    })
                })
                .collect();
            changes.sort_unstable();
            eprintln!(
                "dm-health inference round {}: changed_field_types={} examples={:?}",
                round + 1,
                changes.len(),
                changes.iter().take(12).collect::<Vec<_>>()
            );
        }
    }
    let inference_time = started.elapsed() - registration_time;
    if profile {
        eprintln!(
            "dm-health type profile: registration={:?} inference={:?} evidence={:?} ({} passes) parameters={:?} returns={:?}",
            registration_time, inference_time, evidence_time, evidence_passes, parameter_time, return_time
        );
    }
    // Diagnostic runs can stop once the inference trace is complete, before
    // expensive per-procedure checks. Normal analysis is unaffected.
    if std::env::var("DM_HEALTH_PROFILE_INFERENCE_ONLY").as_deref() == Ok("1") {
        return Ok((checker.findings, checker.coverage));
    }
    if !inference_converged && !inference_cycle {
        checker.findings.push(Finding {
            rule: "parameter-inference-limit",
            path: "<ast>".into(),
            line: 1,
            severity: "error",
            message: "parameter and return inference did not converge within 8 outer rounds".into(),
        });
    }
    let phase = Instant::now();
    checker.prove_initializations();
    let initialization_time = phase.elapsed();
    let phase = Instant::now();
    checker.finalize_fields();
    let field_finalization_time = phase.elapsed();
    let phase = Instant::now();
    checker.check_field_initializers();
    let field_initializer_time = phase.elapsed();
    let phase = Instant::now();
    checker.check_overrides_values();
    let override_values_time = phase.elapsed();
    let phase = Instant::now();
    checker.check_overrides();
    let override_contract_time = phase.elapsed();
    let phase = Instant::now();
    let semantic = structural
        .map(|hash| semantic_digest(&checker, hash))
        .transpose()?;
    if profile {
        eprintln!(
            "dm-health finalization profile: initialization={initialization_time:?} fields={field_finalization_time:?} field-values={field_initializer_time:?} override-values={override_values_time:?} override-contracts={override_contract_time:?} digest={:?}",
            phase.elapsed()
        );
    }
    let checking_started = Instant::now();
    let shard_directory = cache_directory.map(|directory| directory.join("proc-shards"));
    if let Some(directory) = &shard_directory {
        fs::create_dir_all(directory)?;
    }
    let profile_procedures = std::env::var_os("DM_HEALTH_PROFILE").is_some();
    let mut key_time = Duration::ZERO;
    let mut cache_read_time = Duration::ZERO;
    let mut check_time = Duration::ZERO;
    let mut cache_write_time = Duration::ZERO;
    for line in third.lines() {
        let line = line?;
        let item = read_item(&line)?;
        if item["kind"] == "proc" {
            let owner = item["owner"].as_str().unwrap_or("");
            let name = item["name"].as_str().unwrap_or("");
            if matches!(name, "Destroy" | "Del") {
                let started = profile_procedures.then(Instant::now);
                checker.check_proc(&item);
                if let Some(started) = started {
                    check_time += started.elapsed();
                }
                continue;
            }
            if let (Some(shard_directory), Some(semantic)) =
                (shard_directory.as_deref(), semantic.as_deref())
            {
                if !selection.includes(source(&item).0.as_str()) {
                    let started = profile_procedures.then(Instant::now);
                    checker.check_proc(&item);
                    if let Some(started) = started {
                        check_time += started.elapsed();
                    }
                    continue;
                }
                let started = profile_procedures.then(Instant::now);
                let version = checker
                    .checked_versions
                    .get(&(owner.into(), name.into()))
                    .copied()
                    .unwrap_or(0);
                let mut hash = Sha256::new();
                hash_value(&mut hash, semantic.as_bytes());
                hash_value(&mut hash, owner.as_bytes());
                hash_value(&mut hash, name.as_bytes());
                hash_value(&mut hash, &version.to_le_bytes());
                hash_value(&mut hash, &serde_json::to_vec(&item)?);
                let key = format!("{:x}", hash.finalize());
                if let Some(started) = started {
                    key_time += started.elapsed();
                }
                let started = profile_procedures.then(Instant::now);
                let cached = load_proc_shard(shard_directory, &key);
                if let Some(started) = started {
                    cache_read_time += started.elapsed();
                }
                if let Some((findings, delta)) = cached {
                    *checker
                        .checked_versions
                        .entry((owner.into(), name.into()))
                        .or_default() += 1;
                    checker.findings.extend(findings);
                    checker.coverage.add_delta(&delta);
                    checker.coverage.checked_procs_reused += 1;
                    continue;
                }
                // Collect this procedure's coverage separately. Cloning and
                // diffing the cumulative maps for every procedure becomes
                // quadratic once unresolved roots number in the thousands.
                let accumulated = std::mem::take(&mut checker.coverage);
                let finding_start = checker.findings.len();
                let started = profile_procedures.then(Instant::now);
                checker.check_proc(&item);
                if let Some(started) = started {
                    check_time += started.elapsed();
                }
                let delta = std::mem::take(&mut checker.coverage);
                checker.coverage = accumulated;
                checker.coverage.add_delta(&delta);
                let started = profile_procedures.then(Instant::now);
                store_proc_shard(
                    shard_directory,
                    &key,
                    &checker.findings[finding_start..],
                    &delta,
                )?;
                if let Some(started) = started {
                    cache_write_time += started.elapsed();
                }
                checker.coverage.checked_procs_recomputed += 1;
            } else {
                let started = profile_procedures.then(Instant::now);
                checker.check_proc(&item);
                if let Some(started) = started {
                    check_time += started.elapsed();
                }
            }
        }
    }
    if profile_procedures {
        eprintln!(
            "dm-health procedure profile: key={:.3}s cache-read={:.3}s check={:.3}s cache-write={:.3}s",
            key_time.as_secs_f64(),
            cache_read_time.as_secs_f64(),
            check_time.as_secs_f64(),
            cache_write_time.as_secs_f64()
        );
    }
    if profile {
        eprintln!(
            "dm-health type profile: finalization={:?} procedure_check={:?} total={:?} recomputed={} reused={}",
            checking_started.duration_since(started) - registration_time - inference_time,
            checking_started.elapsed(),
            started.elapsed(),
            checker.coverage.checked_procs_recomputed,
            checker.coverage.checked_procs_reused
        );
    }
    Ok((checker.findings, checker.coverage))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn constructor_argument_effects_are_found_inside_call_parameter_wrappers() {
        let initializer = serde_json::json!({"kind":"DMASTNewInferred","fields":{
            "Parameters":[{"kind":"DMASTCallParameter","fields":{
                "Value":{"kind":"DMASTProcCall","fields":{
                    "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"mutate_global"}},
                    "Parameters":[]
                }},"Key":null
            }}]
        }});
        let arguments = f(&initializer, "Parameters").as_array().unwrap();
        assert!(arguments.iter().any(contains_unknown_effect));
    }

    #[test]
    fn proven_global_call_preserves_flow_but_nested_or_shadowed_effects_do_not() {
        let proc = |owner: &str, name: &str, body: serde_json::Value| {
            serde_json::json!({"kind":"proc","owner":owner,"name":name,
                "file":"code/test.dm","line":1,"parameters":[],"returnType":null,
                "body":body})
            .to_string()
        };
        let pure_body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
            "Statements":[{"kind":"DMASTProcStatementReturn","fields":{
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
            }}]
        }});
        let mutation_body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
            "Statements":[{"kind":"DMASTProcStatementExpression","fields":{
                "Expression":{"kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"GLOB"}},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
                }}
            }}]
        }});
        let input = [
            proc("/", "pure_number", pure_body.clone()),
            proc("/", "mutate", mutation_body),
            proc("/datum/shadow", "pure_number", pure_body),
        ]
        .join("\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let call = |name: &str, params: Vec<Value>| {
            serde_json::json!({
                "kind":"DMASTProcCall","fields":{
                    "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":name}},
                    "Parameters":params
                }
            })
        };
        let pure = call("pure_number", vec![]);
        let mutating = call("mutate", vec![]);
        assert!(!contains_unproved_effect(&pure, "/datum/other", &symbols));
        assert!(contains_unproved_effect(&pure, "/datum/shadow", &symbols));
        assert!(contains_unproved_effect(
            &mutating,
            "/datum/other",
            &symbols
        ));
        let nested = call(
            "pure_number",
            vec![serde_json::json!({
                "kind":"DMASTCallParameter","fields":{"Value":mutating,"Key":null}
            })],
        );
        assert!(contains_unproved_effect(&nested, "/datum/other", &symbols));
        let safe_builtin = call(
            "length",
            vec![serde_json::json!({
                "kind":"DMASTCallParameter","fields":{"Value":pure.clone(),"Key":null}
            })],
        );
        assert!(!contains_unproved_effect(
            &safe_builtin,
            "/datum/other",
            &symbols
        ));
        let nested_binary = serde_json::json!({"kind":"DMASTAdd","fields":{
            "LHS":safe_builtin,"RHS":nested.clone()
        }});
        assert!(contains_unproved_effect(
            &nested_binary,
            "/datum/other",
            &symbols
        ));
        let mut env = Env::default();
        env.facts
            .insert("gear_tweaks".into(), Ty::List(Box::new(Ty::Num)));
        env.invalidate_after_checked(&pure, "/datum/other", &symbols);
        assert_eq!(env.facts["gear_tweaks"], Ty::List(Box::new(Ty::Num)));
        env.invalidate_after_checked(&nested, "/datum/other", &symbols);
        assert!(!env.facts.contains_key("gear_tweaks"));
    }

    #[test]
    fn exact_fresh_receiver_method_preserves_existing_flow() {
        let proc = |name: &str, body: serde_json::Value| {
            serde_json::json!({"kind":"proc","owner":"/datum/fresh","name":name,
                "file":"code/test.dm","line":1,"parameters":[],"returnType":null,
                "body":body})
            .to_string()
        };
        let fresh_write = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
            "Statements":[{"kind":"DMASTProcStatementExpression","fields":{
                "Expression":{"kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTDereference","fields":{
                        "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
                        "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"value"}}]
                    }},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
                }}
            }}]
        }});
        let input = [proc("New", fresh_write.clone()), proc("touch", fresh_write)].join("\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let new_object = serde_json::json!({"kind":"DMASTNewPath","fields":{
            "Path":{"kind":"DMASTConstantPath","fields":{
                "Value":{"kind":"DMASTPath","fields":{"Path":"/datum/fresh"}}
            }},"Parameters":[]
        }});
        let call = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":new_object,"Operations":[{
                "kind":"CallOperation","fields":{"Identifier":"touch","Parameters":[]}
            }]
        }});
        assert!(!contains_unproved_effect(&call, "/datum/other", &symbols));
        let mut env = Env::default();
        env.facts.insert("external_field".into(), Ty::Num);
        env.invalidate_after_checked(&call, "/datum/other", &symbols);
        assert_eq!(env.facts["external_field"], Ty::Num);
        let mut unknown = call.clone();
        unknown["fields"]["Operations"][0]["fields"]["Identifier"] = "unknown_method".into();
        assert!(contains_unproved_effect(&unknown, "/datum/other", &symbols));
        let mut effectful_argument = call.clone();
        effectful_argument["fields"]["Operations"][0]["fields"]["Parameters"] = serde_json::json!([{"kind":"DMASTCallParameter","fields":{
            "Value":{"kind":"DMASTCall","fields":{}},"Key":null
        }}]);
        assert!(contains_unproved_effect(
            &effectful_argument,
            "/datum/other",
            &symbols
        ));
    }

    #[test]
    fn typed_receiver_dispatch_requires_every_override_to_be_effect_free() {
        let body = |mutates: bool| {
            let value = if mutates {
                serde_json::json!({"kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"GLOB"}},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
                }})
            } else {
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}})
            };
            serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
                "Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":value}}]
            }})
        };
        let proc = |owner: &str, mutates: bool| {
            serde_json::json!({
                "kind":"proc","owner":owner,"name":"inspect","file":"code/test.dm",
                "line":1,"parameters":[],"returnType":null,"body":body(mutates)
            })
            .to_string()
        };
        let safe = [proc("/datum/base", false), proc("/datum/base/child", false)].join("\n");
        let symbols = Symbols::collect(safe.as_bytes(), &[]).unwrap();
        let call = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"receiver"}},
            "Operations":[{"kind":"CallOperation","fields":{
                "Identifier":"inspect","Parameters":[]
            }}]
        }});
        let vars = HashMap::from([("receiver".into(), Ty::Path("/datum/base".into()))]);
        assert!(!contains_unproved_effect_with_vars(
            &call,
            "/datum/other",
            &symbols,
            &vars
        ));
        let unsafe_source = format!("{safe}\n{}", proc("/datum/base/bad", true));
        let unsafe_symbols = Symbols::collect(unsafe_source.as_bytes(), &[]).unwrap();
        assert!(contains_unproved_effect_with_vars(
            &call,
            "/datum/other",
            &unsafe_symbols,
            &vars
        ));
        assert!(contains_unproved_effect_with_vars(
            &call,
            "/datum/other",
            &symbols,
            &HashMap::new()
        ));
    }
    #[test]
    fn oscillating_field_widens_once_and_stays_unknown() {
        let key = ("/atom".to_owned(), "color".to_owned());
        let field = FieldInfo {
            ty: Ty::Text,
            explicit_type: false,
            evidence: Ty::Text,
            origin: serde_json::json!({"file":"code/test.dm","line":3}),
            nullable: false,
            delayed: false,
            phase: None,
            proved_initialization: false,
            initially_null: false,
            saw_unknown_write: false,
            conflict: false,
        };
        let mut fields = HashMap::from([(key.clone(), field)]);
        let before = HashMap::from([(key.clone(), Ty::Unknown)]);
        let prior = HashMap::from([(key.clone(), Ty::Text)]);
        let mut locked = HashSet::new();
        let findings = widen_oscillating_fields(&mut fields, &before, Some(&prior), &mut locked);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].rule, "cyclic-field-inference");
        assert_eq!(findings[0].severity, "warning");
        assert_eq!(fields[&key].ty, Ty::Unknown);
        assert_eq!(fields[&key].evidence, Ty::Unknown);
        fields.get_mut(&key).unwrap().ty = Ty::Text;
        fields.get_mut(&key).unwrap().evidence = Ty::Text;
        assert!(
            widen_oscillating_fields(&mut fields, &before, Some(&prior), &mut locked).is_empty()
        );
        assert_eq!(fields[&key].ty, Ty::Unknown);
        assert_eq!(fields[&key].evidence, Ty::Unknown);
    }

    #[test]
    fn builtin_world_time_and_typed_input_are_precise() {
        assert_eq!(builtin_field_type("/world", "time"), Some(Ty::Num));
        assert_eq!(
            builtin_field_type("/atom", "name"),
            Some(Ty::parse("text?"))
        );
        assert_eq!(builtin_field_type("/atom", "dir"), Some(Ty::Num));
        assert_eq!(
            builtin_field_type("/datum", "type"),
            Some(Ty::parse("typepath</datum>"))
        );
        assert_eq!(
            builtin_field_type("/world", "view"),
            Some(Ty::OneOf(vec![Ty::Num, Ty::Text]))
        );
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let world_time = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"world"}},
            "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"time","Safe":false}}]
        }});
        assert_eq!(
            checker.expression(&world_time, &HashMap::new(), "/datum/test"),
            Ty::Num
        );
        let image = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProc","fields":{"Identifier":"image"}},
            "Parameters":[]
        }});
        assert_eq!(
            checker.expression(&image, &HashMap::new(), "/datum/test"),
            Ty::OneOf(vec![Ty::Path("/image".into()), Ty::Num])
        );
        for (name, count, expected) in [
            ("block", 2, Ty::List(Box::new(Ty::Path("/turf".into())))),
            ("block", 3, Ty::List(Box::new(Ty::Path("/turf".into())))),
            ("sound", 1, Ty::Path("/sound".into())),
            ("file", 1, Ty::Primitive("file".into())),
            ("json_encode", 1, Ty::Text),
            ("splittext", 2, Ty::List(Box::new(Ty::Text))),
            ("sleep", 1, Ty::Void),
            ("flick", 2, Ty::Void),
        ] {
            let call = serde_json::json!({"kind":"DMASTProcCall","fields":{
                "Callable":{"kind":"DMASTCallableProc","fields":{"Identifier":name}},
                "Parameters":(0..count).map(|_| serde_json::json!({
                    "Key":null,"Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
                })).collect::<Vec<_>>()
            }});
            assert_eq!(
                checker.expression(&call, &HashMap::new(), "/datum/test"),
                expected,
                "{name}"
            );
        }
        let clamp_args = (1..=3)
            .map(|number| {
                serde_json::json!({"fields":{
                    "Key":null,"Value":{"kind":"DMASTConstantInteger","fields":{"Value":number}}
                }
                })
            })
            .collect::<Vec<_>>();
        let clamp = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProc","fields":{"Identifier":"clamp"}},
            "Parameters":clamp_args
        }});
        assert_eq!(
            checker.expression(&clamp, &HashMap::new(), "/datum/test"),
            Ty::Num
        );
        let typed_clamp_args = ["value", "low", "high"].into_iter().map(|name| serde_json::json!({
            "fields":{"Key":null,"Value":{"kind":"DMASTIdentifier","fields":{"Identifier":name}}}
        })).collect::<Vec<_>>();
        let typed_clamp = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProc","fields":{"Identifier":"clamp"}},
            "Parameters":typed_clamp_args
        }});
        for ty in [
            Ty::Path("/pixloc".into()),
            Ty::Path("/vector".into()),
            Ty::Text,
        ] {
            let vars = HashMap::from([
                ("value".into(), Ty::List(Box::new(ty.clone()))),
                ("low".into(), ty.clone()),
                ("high".into(), ty.clone()),
            ]);
            assert_eq!(
                checker.expression(&typed_clamp, &vars, "/datum/test"),
                Ty::List(Box::new(ty.clone()))
            );
            if matches!(ty, Ty::Path(_)) {
                let scalar = HashMap::from([
                    ("value".into(), ty.clone()),
                    ("low".into(), ty.clone()),
                    ("high".into(), ty.clone()),
                ]);
                assert_eq!(checker.expression(&typed_clamp, &scalar, "/datum/test"), ty);
            }
        }
        let input =
            serde_json::json!({"kind":"DMASTInput","fields":{"Types":"Null, Text","List":null}});
        assert_eq!(
            checker.expression(&input, &HashMap::new(), "/datum/test"),
            Ty::parse("text?")
        );
        let choices = serde_json::json!({"kind":"DMASTInput","fields":{
            "Types":null,"List":{"kind":"DMASTIdentifier","fields":{"Identifier":"options"}}}});
        let vars = HashMap::from([("options".into(), Ty::parse("list</obj/item>"))]);
        assert_eq!(
            checker.expression(&choices, &vars, "/datum/test"),
            Ty::parse("/obj/item?")
        );
    }

    #[test]
    fn topic_entry_parameters_have_engine_types() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let topic = serde_json::json!({"kind":"proc","owner":"/datum/admins","name":"Topic",
        "file":"code/admin.dm","line":1,"returnType":null,"body":null,
        "parameters":[
            {"Name":"href","type":null,"valueType":null,"defaultValue":null},
            {"Name":"href_list","type":"/list","valueType":null,"defaultValue":null}
        ]});
        checker.register(&topic);
        let params = &checker.procs[&("/datum/admins".into(), "Topic".into())].parameters;
        assert_eq!(params[0].ty, Ty::Text);
        assert_eq!(
            params[1].ty,
            Ty::Assoc(Box::new(Ty::Text), Box::new(Ty::Text))
        );
    }

    #[test]
    fn literal_preference_read_uses_inherited_deserializer_shape() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        for (owner, name) in [
            ("/datum/preferences", "read_preference"),
            ("/datum/preference/toggle", "pref_deserialize"),
        ] {
            checker.register(&serde_json::json!({"kind":"proc","owner":owner,"name":name,
                "file":"code/preferences.dm","line":1,"parameters":[],"returnType":null,"body":null}));
        }
        let args = serde_json::json!([{"kind":"DMASTCallParameter","fields":{
            "Key":null,"Value":{"kind":"DMASTConstantPath","fields":{
                "Value":{"kind":"DMASTPath","fields":{
                    "Path":"/datum/preference/toggle/human/test"}}}}}}]);
        assert_eq!(
            checker.preference_read_result(
                "/datum/preferences",
                "read_preference",
                &args,
                &HashMap::new(),
                "/datum/test"
            ),
            Some(Ty::Num)
        );
        checker.register(&serde_json::json!({"kind":"proc",
            "owner":"/datum/preference/toggle/human/test","name":"pref_deserialize",
            "file":"code/test.dm","line":2,"parameters":[],"returnType":null,"body":null}));
        assert_eq!(
            checker.preference_read_result(
                "/datum/preferences",
                "read_preference",
                &args,
                &HashMap::new(),
                "/datum/test"
            ),
            None
        );
        checker.register(&serde_json::json!({"kind":"proc",
            "owner":"/datum/preference/numeric","name":"pref_deserialize",
            "file":"code/preferences.dm","line":3,"parameters":[],"returnType":null,"body":null}));
        let numeric_args = serde_json::json!([{"kind":"DMASTCallParameter","fields":{
            "Key":null,"Value":{"kind":"DMASTConstantPath","fields":{
                "Value":{"kind":"DMASTPath","fields":{
                    "Path":"/datum/preference/numeric/human/age"}}}}}}]);
        assert_eq!(
            checker.preference_read_result(
                "/datum/preferences",
                "read_preference",
                &numeric_args,
                &HashMap::new(),
                "/datum/test"
            ),
            None,
            "numeric defaults must be proved before specializing"
        );
    }

    #[test]
    fn weakref_resolve_is_nullable_datum_only_for_original_proc() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.register(&serde_json::json!({"kind":"proc","owner":"/datum/weakref",
            "name":"resolve","file":"code/datums/weakrefs.dm","line":75,
            "parameters":[],"returnType":null,"body":null}));
        assert_eq!(
            checker.weakref_resolve_result("/datum/weakref", "resolve", &serde_json::json!([])),
            Some(Ty::Nullable(Box::new(Ty::Path("/datum".into()))))
        );
        assert_eq!(
            checker.weakref_resolve_result("/datum/weakref", "resolve", &serde_json::json!([{}])),
            None
        );
        checker.register(
            &serde_json::json!({"kind":"proc","owner":"/datum/weakref/special",
            "name":"resolve","file":"code/test.dm","line":1,
            "parameters":[],"returnType":null,"body":null}),
        );
        assert_eq!(
            checker.weakref_resolve_result(
                "/datum/weakref/special",
                "resolve",
                &serde_json::json!([])
            ),
            None
        );
    }

    #[test]
    fn collection_join_preserves_shared_element_supertype() {
        let symbols = Symbols::default();
        let left = Ty::List(Box::new(Ty::Path("/obj/item".into())));
        let right = Ty::List(Box::new(Ty::Path("/obj/structure".into())));
        assert_eq!(
            left.join(&right, &symbols),
            Ty::List(Box::new(Ty::Path("/obj".into())))
        );
        let incompatible = Ty::List(Box::new(Ty::Text));
        assert!(!left.join(&incompatible, &symbols).is_precise());
    }

    #[test]
    fn unknown_expression_roots_point_to_field_declaration() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"value",
            "file":"code/test.dm","line":2,"type":null,"valueType":"anything",
            "initializer":null});
        let use_field = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Use",
            "file":"code/test.dm","line":4,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{
                "Expression":{"kind":"DMASTIdentifier","file":"code/test.dm","line":5,
                    "fields":{"Identifier":"value"}}}}]}}});
        let source = format!("{field}\n{use_field}\n");
        let (_, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(coverage
            .unresolved_roots
            .values()
            .any(|root| root.category == "Field"
                && root.symbol == "/datum/test.value"
                && root.path == "code/test.dm"
                && root.line == 2
                && root.count > 0));
    }

    #[test]
    fn unknown_operator_root_descends_to_unknown_field() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"value",
            "file":"code/test.dm","line":2,"type":null,"valueType":"anything",
            "initializer":null});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Use",
        "file":"code/test.dm","line":4,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAdd","file":"code/test.dm","line":5,"fields":{
                "LHS":{"kind":"DMASTIdentifier","file":"code/test.dm","line":5,"fields":{"Identifier":"value"}},
                "RHS":{"kind":"DMASTConstantInteger","file":"code/test.dm","line":5,"fields":{"Value":1}}
            }}}}]}}});
        let source = format!("{field}\n{proc}\n");
        let (_, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(coverage
            .unresolved_roots
            .values()
            .any(|root| root.category == "Field"
                && root.symbol == "/datum/test.value"
                && root.count >= 2));
    }

    #[test]
    fn unknown_chained_call_root_uses_final_receiver() {
        let prefs = serde_json::json!({"kind":"field","owner":"/client","name":"prefs",
            "file":"code/client.dm","line":2,"type":"/datum/preferences","valueType":null,
            "initializer":{"kind":"DMASTConstantNull","fields":{}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Use",
        "file":"code/test.dm","line":4,"parameters":[{"Name":"C","type":"/client",
        "valueType":null,"defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTDereference","file":"code/test.dm","line":5,
                "fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"C"}},
                "Operations":[
                    {"kind":"FieldOperation","fields":{"Identifier":"prefs","Safe":true}},
                    {"kind":"CallOperation","fields":{"Identifier":"missing","Safe":true,"Parameters":[]}}
                ]}}}}]}}});
        let source = format!("{prefs}\n{proc}\n");
        let (_, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            coverage
                .unresolved_roots
                .values()
                .any(|root| root.category == "Member return"
                    && root.symbol == "/datum/preferences/missing"),
            "{:?}",
            coverage.unresolved_roots
        );
    }

    #[test]
    fn field_write_flow_preserves_same_type_after_simple_if() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let write = |value: Value| {
            serde_json::json!({"kind":"DMASTProcStatementExpression",
            "fields":{"Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}},
                "RHS":value}}}})
        };
        let branch = |value: Value| {
            serde_json::json!({"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[write(value)]}})
        };
        let condition = serde_json::json!({"kind":"DMASTIdentifier",
            "fields":{"Identifier":"condition"}});
        let number = serde_json::json!({"kind":"DMASTConstantInteger",
            "fields":{"Value":1}});
        let decision = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
            "Condition":condition,
            "Body":branch(number.clone()),
            "ElseBody":branch(number)}});
        let prior = HashMap::from([("value".into(), Ty::Null), ("condition".into(), Ty::Num)]);
        let locals = HashSet::from(["value".into(), "condition".into()]);
        let after = checker
            .simple_if_local_facts(&decision, "/datum/test", &prior, &locals)
            .unwrap();
        assert_eq!(after["value"], Ty::Num);

        let early_return = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
            "Statements":[{"kind":"DMASTProcStatementIf","fields":{
                "Condition":{"kind":"DMASTIdentifier","fields":{"Identifier":"condition"}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                    {"kind":"DMASTProcStatementReturn","fields":{"Value":null}}]}},
                "ElseBody":branch(serde_json::json!({"kind":"DMASTConstantInteger",
                    "fields":{"Value":2}}))}}]}});
        let mut flow = LocalTypeFlow {
            facts: prior,
            assigned: HashSet::new(),
        };
        checker.scan_local_type_flow(&early_return, "/datum/test", &mut flow, &mut HashMap::new());
        assert_eq!(flow.facts["value"], Ty::Num);

        let field_key = ("/datum/test".into(), "field".into());
        checker.fields.insert(
            field_key.clone(),
            FieldInfo {
                ty: Ty::Unknown,
                explicit_type: false,
                evidence: Ty::Null,
                origin: serde_json::json!({"file":"code/test.dm","line":1}),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let unreachable = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
        "Statements":[
            {"kind":"DMASTProcStatementReturn","fields":{"Value":null}},
            {"kind":"DMASTProcStatementExpression","fields":{
                "Expression":{"kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"field"}},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":3}}}}}}
        ]}});
        checker.register_writes(&unreachable, "/datum/test", &HashMap::new(), &locals);
        assert_eq!(checker.fields[&field_key].evidence, Ty::Null);
    }

    #[test]
    fn stale_field_root_points_to_invalidating_call() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.fields.insert(
            ("/datum/test".into(), "items".into()),
            FieldInfo {
                ty: Ty::List(Box::new(Ty::Num)),
                explicit_type: true,
                evidence: Ty::Unknown,
                origin: serde_json::json!({"file":"code/test.dm","line":2}),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: true,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let mut env = Env::default();
        let call = serde_json::json!({"kind":"DMASTProcCall","file":"code/test.dm","line":7,
            "fields":{"Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"unknown_call"}},"Parameters":[]}});
        env.invalidate_after(&call);
        let read = serde_json::json!({"kind":"DMASTIdentifier","file":"code/test.dm","line":8,
            "fields":{"Identifier":"items"}});
        let root = checker.unknown_root(&read, "/datum/test", &env, 0);
        assert_eq!(root.category, "Unknown side effect");
        assert_eq!(root.path, "code/test.dm");
        assert_eq!(root.line, 7);
        env.record_fact_origin(
            "items",
            &Ty::Unknown,
            &serde_json::json!({"file":"code/test.dm","line":9}),
        );
        env.facts.insert("items".into(), Ty::Unknown);
        let root = checker.unknown_root(&read, "/datum/test", &env, 0);
        assert_eq!(root.category, "Unverified value write");
        assert_eq!(root.line, 9);
    }

    #[test]
    fn precise_local_with_unknown_written_value_points_to_write() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let mut env = Env::default();
        env.slots.insert("value".into(), Ty::Num);
        env.facts.insert("value".into(), Ty::Unknown);
        let write = serde_json::json!({"kind":"DMASTAssign","file":"code/test.dm","line":7});
        env.record_fact_origin("value", &Ty::Unknown, &write);
        let read = serde_json::json!({"kind":"DMASTIdentifier","file":"code/test.dm","line":8,
            "fields":{"Identifier":"value"}});
        let root = checker.unknown_root(&read, "/datum/test", &env, 0);
        assert_eq!(root.category, "Unverified value write");
        assert_eq!(root.line, 7);
        env.origins
            .insert("value".into(), ("code/test.dm".into(), 2));
        env.slots
            .insert("value".into(), Ty::List(Box::new(Ty::Unknown)));
        let root = checker.unknown_root(&read, "/datum/test", &env, 0);
        assert_eq!(root.category, "Unverified value write");
        assert_eq!(root.line, 7);
    }

    #[test]
    fn unknown_local_root_points_to_local_declaration() {
        let local = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":5,"fields":{"Name":"value","Type":null,
            "ValueType":"anything","Value":{"kind":"DMASTProcCall","fields":{
                "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Mystery"}},
                "Parameters":[]}},"IsGlobal":false}});
        let read = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTIdentifier","file":"code/test.dm","line":6,
                "fields":{"Identifier":"value"}}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Use",
            "file":"code/test.dm","line":4,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[local,read]}}});
        let source = format!("{proc}\n");
        let (_, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(coverage
            .unresolved_roots
            .values()
            .any(|root| root.category == "Local"
                && root.symbol == "/datum/test/Use:value"
                && root.line == 5));
    }

    #[test]
    fn typed_list_field_infers_element_from_append() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"names",
            "file":"code/test.dm","line":1,"type":"/list","valueType":null,
            "initializer":{"kind":"DMASTList","fields":{"Values":[]}}});
        let append = serde_json::json!({"kind":"DMASTAppend","file":"code/test.dm","line":3,
            "fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"names"}},
            "RHS":{"kind":"DMASTConstantString","fields":{"Value":"alpha"}}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Add",
            "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":append}}]}}});
        let source = format!("{field}\n{proc}\n");
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings.iter().any(
            |finding| finding.rule == "unknown-field-type" && finding.message.contains("names")
        ));
        assert!(coverage.known_declarations > 0);

        let mixed = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"AddNumber",
        "file":"code/test.dm","line":4,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAppend","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"names"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":7}}
            }}
        }}]}}});
        let mixed_source = format!("{source}{mixed}\n");
        let (mixed_findings, _) = analyze(
            mixed_source.as_bytes(),
            mixed_source.as_bytes(),
            mixed_source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(mixed_findings
            .iter()
            .any(|finding| finding.rule == "field-type-conflict"
                && finding.message.contains("names")));
    }

    #[test]
    fn keyed_field_writes_keep_heterogeneous_nullable_values_separate() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let key = ("/datum/test".into(), "base_values".into());
        checker.fields.insert(
            key.clone(),
            FieldInfo {
                ty: Ty::List(Box::new(Ty::Unknown)),
                explicit_type: true,
                evidence: Ty::EmptyList,
                origin: Value::Null,
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let vars = HashMap::new();
        assert!(!checker.merge_keyed_field_write(
            &key,
            None,
            &serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
            &vars,
            "/datum/test",
        ));
        assert!(checker.merge_keyed_field_write(
            &key,
            Some("desc"),
            &serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"description"}}),
            &vars,
            "/datum/test",
        ));
        assert!(checker.merge_keyed_field_write(
            &key,
            Some("armor"),
            &serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":7}}),
            &vars,
            "/datum/test",
        ));
        assert!(checker.infer_field_types());
        let Ty::Record(members) = &checker.fields[&key].ty else {
            panic!("expected record")
        };
        assert_eq!(members["desc"].0, Ty::Text);
        assert_eq!(members["armor"].0, Ty::Num);
        assert!(!checker.fields[&key].conflict);
        let read = |name: &str| {
            serde_json::json!({"kind":"DMASTDereference","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"base_values"}},
                "Operations":[{"kind":"IndexOperation","fields":{
                    "Index":{"kind":"DMASTConstantString","fields":{"Value":name}}
                }}]
            }})
        };
        assert_eq!(
            checker.expression(&read("desc"), &vars, "/datum/test"),
            Ty::Nullable(Box::new(Ty::Text))
        );
        assert_eq!(
            checker.expression(&read("armor"), &vars, "/datum/test"),
            Ty::Nullable(Box::new(Ty::Num))
        );
        let nullable =
            serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"maybe"}});
        let vars = HashMap::from([("maybe".into(), Ty::Nullable(Box::new(Ty::Text)))]);
        checker.fields.get_mut(&key).unwrap().evidence = Ty::EmptyList;
        let indexed_write = serde_json::json!({"kind":"DMASTAssign","fields":{
            "LHS":read("desc"), "RHS":nullable,
        }});
        checker.register_writes(&indexed_write, "/datum/test", &vars, &HashSet::new());
        assert_eq!(
            checker.fields[&key].evidence,
            Ty::Record(BTreeMap::from([(
                "desc".into(),
                (Ty::Nullable(Box::new(Ty::Text)), true)
            )]))
        );
        assert!(checker.merge_keyed_field_write(&key, None, &nullable, &vars, "/datum/test"));
        assert_eq!(checker.fields[&key].evidence, Ty::Unknown);
    }

    #[test]
    fn numeric_index_recurrence_seeds_empty_list_value_type() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let key = ("/datum/test".into(), "amounts".into());
        checker.fields.insert(
            key.clone(),
            FieldInfo {
                ty: Ty::List(Box::new(Ty::Unknown)),
                explicit_type: true,
                evidence: Ty::EmptyList,
                origin: Value::Null,
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let index = serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"key"}});
        let old = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"amounts"}},
            "Operations":[{"kind":"IndexOperation","fields":{"Index":index}}]
        }});
        let rhs = serde_json::json!({"kind":"DMASTAdd","fields":{
            "LHS":{"kind":"DMASTExpressionWrapped","fields":{"Value":{
                "kind":"DMASTOr","fields":{
                    "LHS":{"kind":"DMASTTernary","fields":{
                        "A":{"kind":"DMASTIdentifier","fields":{"Identifier":"amounts"}},
                        "B":old,
                        "C":{"kind":"DMASTConstantNull","fields":{}}
                    }},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":0}}
                }
            }}},
            "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"increment"}}
        }});
        let vars = HashMap::from([("key".into(), Ty::Text), ("increment".into(), Ty::Num)]);
        assert!(checker.numeric_index_recurrence(&rhs, &key, &vars, "/datum/test"));
        let write = serde_json::json!({"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTDereference","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"amounts"}},
                "Operations":[{"kind":"IndexOperation","fields":{"Index":index}}]
            }},
            "RHS":rhs
        }});
        checker.register_writes(&write, "/datum/test", &vars, &HashSet::new());
        assert_eq!(
            checker.fields[&key].evidence,
            Ty::Assoc(Box::new(Ty::Text), Box::new(Ty::Num))
        );
        checker.fields.get_mut(&key).unwrap().evidence = Ty::EmptyList;
        let mut non_numeric = vars;
        non_numeric.insert("increment".into(), Ty::Text);
        assert!(!checker.numeric_index_recurrence(
            f(&write, "RHS"),
            &key,
            &non_numeric,
            "/datum/test"
        ));
    }

    #[test]
    fn empty_list_field_evidence_survives_inference_rounds() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let key = ("/datum/test".into(), "amounts".into());
        checker.fields.insert(
            key.clone(),
            FieldInfo {
                ty: Ty::List(Box::new(Ty::Unknown)),
                explicit_type: true,
                evidence: Ty::Null,
                origin: Value::Null,
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: true,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        checker.merge_field_write(&key, Ty::EmptyList);
        checker.infer_field_types();
        assert_eq!(checker.fields[&key].ty, Ty::EmptyList);
        checker.fields.get_mut(&key).unwrap().evidence = Ty::Null;
        checker.merge_field_write(&key, Ty::EmptyList);
        assert_eq!(checker.fields[&key].evidence, Ty::EmptyList);
        checker.merge_field_write(&key, Ty::Assoc(Box::new(Ty::Text), Box::new(Ty::Num)));
        checker.infer_field_types();
        assert_eq!(
            checker.fields[&key].ty,
            Ty::Assoc(Box::new(Ty::Text), Box::new(Ty::Num))
        );
        assert!(!checker.fields[&key].saw_unknown_write);
    }

    #[test]
    fn list_field_infers_key_and_value_from_index_writes() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"settings",
            "file":"code/test.dm","line":1,"type":"/list","valueType":null,
            "initializer":{"kind":"DMASTList","fields":{"Values":[]}}});
        let write = serde_json::json!({"kind":"DMASTAssign","file":"code/test.dm","line":3,
            "fields":{"LHS":{"kind":"DMASTDereference","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"settings"}},
                "Operations":[{"kind":"IndexOperation","fields":{
                    "Index":{"kind":"DMASTConstantString","fields":{"Value":"enabled"}},
                    "Safe":false}}]}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Set",
            "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":write}}]}}});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-field-type"
                && finding.message.contains("settings")));
    }

    #[test]
    fn nullable_text_index_preserves_collection_shape_through_teardown() {
        let field = serde_json::json!({"kind":"field","owner":"/obj/item","name":"composition",
            "file":"code/test.dm","line":1,"type":"/list","valueType":null,
            "initializer":null});
        let name = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
            "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"name","Safe":false}}]}});
        let write = serde_json::json!({"kind":"DMASTAssign","file":"code/test.dm","line":3,
            "fields":{"LHS":{"kind":"DMASTDereference","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"composition"}},
                "Operations":[{"kind":"IndexOperation","fields":{"Index":name,"Safe":false}}]}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        let clear = serde_json::json!({"kind":"DMASTAssign","file":"code/test.dm","line":4,
            "fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"composition"}},
                "RHS":{"kind":"DMASTConstantNull"}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/obj/item","name":"Set",
        "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":write}},
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":clear}}
        ]}}});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-field-type"
                    && finding.message.contains("composition")),
            "{findings:?}"
        );
    }

    #[test]
    fn project_proc_cannot_shadow_a_type_test_guard() {
        let project_proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
            "name":"isnum","file":"code/test.dm","line":1,
            "parameters":[],"body":null});
        let standard_proc = serde_json::json!({"kind":"proc","owner":"/",
            "name":"isnum","file":"_Standard.dm","line":1,
            "parameters":[],"body":null});
        let source = format!("{}\n{}\n", standard_proc, project_proc);
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(
            findings
                .iter()
                .filter(|f| f.rule == "shadowed-type-guard")
                .count(),
            1
        );
        assert!(findings
            .iter()
            .any(|f| f.rule == "shadowed-type-guard" && f.path == "code/test.dm"));
    }

    #[test]
    fn coverage_explains_untyped_parameter_and_counts_exact_null() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Read",
        "file":"code/test.dm","line":1,"parameters":[{"Name":"value",
            "type":null,"valueType":null,"defaultValue":null}],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementReturn","file":"code/test.dm","line":2,
                "fields":{"Value":{"kind":"DMASTIdentifier","file":"code/test.dm",
                    "line":2,"fields":{"Identifier":"value"}}}}
        ]}}});
        let source = proc.to_string();
        let (_, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(
            coverage.unresolved_causes.get("Local or parameter type"),
            Some(&1)
        );
        assert_eq!(coverage.unresolved_expressions, 1);
        let mut null_proc = proc;
        null_proc["body"]["fields"]["Statements"][0]["fields"]["Value"] =
            serde_json::json!({"kind":"DMASTConstantNull","file":"code/test.dm","line":2});
        let null_source = null_proc.to_string();
        let (_, null_coverage) = analyze(
            null_source.as_bytes(),
            null_source.as_bytes(),
            null_source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(null_coverage.typed_expressions, 1);
        assert_eq!(null_coverage.unresolved_expressions, 0);
    }

    #[test]
    fn numeric_builtins_infer_only_proved_results() {
        let integer = |value| {
            serde_json::json!({"kind":"DMASTConstantInteger",
            "file":"code/test.dm","line":2,"fields":{"Value":value}})
        };
        let call = |name: &str, args: Vec<Value>| {
            serde_json::json!({
            "kind":"DMASTProcCall","file":"code/test.dm","line":2,"fields":{
                "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":name}},
                "Parameters":args.into_iter().map(|value| serde_json::json!({
                    "kind":"DMASTCallParameter","fields":{"Value":value,"Key":null}})).collect::<Vec<_>>()
            }})
        };
        let good = call("min", vec![call("round", vec![integer(4)]), integer(95)]);
        assert!(!contains_unknown_effect(&good));
        assert!(!contains_unknown_effect(&call(
            "max",
            vec![integer(1), integer(2)]
        )));
        assert!(!contains_unknown_effect(&call("view", vec![integer(7)])));
        assert!(contains_unknown_effect(&call(
            "min",
            vec![call("sleep", vec![integer(1)]), integer(2)]
        )));
        let mixed = call(
            "min",
            vec![
                integer(4),
                serde_json::json!({
            "kind":"DMASTConstantString","fields":{"Value":"four"}}),
            ],
        );
        let make_proc = |name: &str, value: Value| {
            serde_json::json!({
            "kind":"proc","owner":"/datum/test","name":name,"file":"code/test.dm",
            "line":1,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementReturn",
                "file":"code/test.dm","line":2,"fields":{"Value":value}}]}}})
        };
        let standard = |name: &str| {
            serde_json::json!({
                "kind":"proc","owner":"/","name":name,"file":"_Standard.dm",
                "line":1,"parameters":[{"Name":"A","type":null,
                    "valueType":null,"defaultValue":null}],"body":null
            })
        };
        let source = format!(
            "{}\n{}\n{}\n{}\n{}\n{}\n",
            standard("min"),
            standard("round"),
            standard("view"),
            make_proc("Good", good),
            make_proc("Mixed", mixed),
            make_proc("See", call("view", vec![integer(7)]))
        );
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"
                && finding.message.contains("/Good")));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"
                && finding.message.contains("/Mixed")));
        assert!(!findings.iter().any(
            |finding| finding.rule == "unknown-return-type" && finding.message.contains("/See")
        ));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unresolved-direct-call"
                && finding.message.contains("min arguments")));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-argument-target"));
    }

    #[test]
    fn max_and_clamp_keep_numeric_result_with_unknown_operand() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let argument = |value: Value| serde_json::json!({"kind":"DMASTCallParameter","fields":{"Key":null,"Value":value}});
        let unknown =
            serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"dynamic"}});
        let number = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":5}});
        let text = serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"a"}});
        assert_eq!(
            checker.builtin_result(&Value::Null, "max", &HashMap::new(), "/datum/test"),
            None
        );
        let call = |args: Vec<Value>| serde_json::json!({"fields":{"Parameters":args}});
        assert_eq!(
            checker.builtin_result(
                &call(vec![argument(number.clone()), argument(unknown.clone())]),
                "max",
                &HashMap::new(),
                "/datum/test"
            ),
            Some(Ty::parse("num?"))
        );
        assert_eq!(
            checker.builtin_result(
                &call(vec![argument(text), argument(unknown.clone())]),
                "min",
                &HashMap::new(),
                "/datum/test"
            ),
            Some(Ty::parse("text?"))
        );
        assert_eq!(
            checker.builtin_result(
                &call(vec![
                    argument(number.clone()),
                    argument(unknown.clone()),
                    argument(number)
                ]),
                "clamp",
                &HashMap::new(),
                "/datum/test"
            ),
            Some(Ty::Num)
        );
        assert_eq!(
            checker.builtin_result(
                &call(vec![argument(unknown.clone()), argument(unknown.clone())]),
                "max",
                &HashMap::new(),
                "/datum/test"
            ),
            Some(Ty::Unknown)
        );
        assert_eq!(
            checker.builtin_result(
                &call(vec![
                    argument(
                        serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}})
                    ),
                    argument(
                        serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"x"}})
                    ),
                    argument(unknown)
                ]),
                "max",
                &HashMap::new(),
                "/datum/test"
            ),
            Some(Ty::Unknown)
        );
    }

    #[test]
    fn round_result_is_numeric_while_unknown_argument_is_reported() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Rounded","file":"code/test.dm","line":1,
        "parameters":[{"Name":"value","type":null,"valueType":null,"defaultValue":null}],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
            "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":2,
            "fields":{"Value":{"kind":"DMASTProcCall","file":"code/test.dm","line":2,
                "fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                    "fields":{"Identifier":"round"}},"Parameters":[{
                    "kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                        "kind":"DMASTIdentifier","fields":{"Identifier":"value"}}}}]}}}
        }]}}});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-type-flow"
                && finding.message.contains("round argument")));
    }

    #[test]
    fn override_inherits_proved_parent_parameter_type() {
        let parent = serde_json::json!({"kind":"proc","owner":"/datum/base",
            "name":"Run","file":"code/test.dm","line":1,
            "parameters":[{"Name":"value","type":null,"valueType":null,"defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let child = serde_json::json!({"kind":"proc","owner":"/datum/base/child",
            "name":"Run","file":"code/test.dm","line":5,
            "parameters":[{"Name":"renamed","type":null,"valueType":null,"defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let source = format!("{parent}\n{child}\n");
        let contracts = crate::contracts::collect(
            "// dm-health: param value num\n/datum/base/proc/Run(value)\n",
        );
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-parameter-type"
                && finding.message.contains("/datum/base/child/Run: renamed")));
        let narrow_contracts = crate::contracts::collect(
            "// dm-health: param value /datum\n/datum/base/proc/Run(value)\n\
             // dm-health: param renamed /datum/base/child\n/datum/base/child/proc/Run(renamed)\n",
        );
        let (narrow_findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &narrow_contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(narrow_findings
            .iter()
            .any(|finding| finding.rule == "override-contract"
                && finding.message.contains("narrows accepted type")));
    }

    #[test]
    fn side_effect_only_proc_has_void_result_even_with_unknown_calls() {
        let call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"External"}},
            "Parameters":[]}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Do",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":2,
                "fields":{"Expression":call}}
            ]}}});
        let source = format!("{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"));
        let implicit = serde_json::json!({"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTCallableSelf"},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
        }});
        assert!(has_implicit_result_assignment(&implicit));
    }

    #[test]
    fn parent_call_uses_proved_own_return_when_virtual_return_is_unknown() {
        let base = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let parent_call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableSuper"},"Parameters":[]}});
        let child = serde_json::json!({"kind":"proc","owner":"/datum/test/child","name":"Run",
        "file":"code/test.dm","line":3,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":4,
                "fields":{"Expression":{"kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTCallableSelf"},"RHS":parent_call}}}}
            ]}}});
        let unknown_call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Mystery"}},
            "Parameters":[]}});
        let other = serde_json::json!({"kind":"proc","owner":"/datum/test/other","name":"Run",
        "file":"code/test.dm","line":6,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":7,
                "fields":{"Value":unknown_call}}
            ]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Caller",
        "file":"code/test.dm","line":9,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":10,
                "fields":{"Value":{"kind":"DMASTProcCall","fields":{
                    "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Run"}},
                    "Parameters":[]}}}}
            ]}}});
        let source = format!("{base}\n{child}\n{other}\n{caller}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"
                && finding.message.starts_with("/datum/test/child/Run ")));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"
                && finding.message.starts_with("/datum/test/other/Run ")));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"
                && finding.message.starts_with("/datum/test/Caller ")));
    }

    #[test]
    fn field_write_evidence_tracks_guarded_local_type() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test",
            "name":"result","file":"code/test.dm","line":1,
            "type":null,"valueType":null,"initializer":null});
        let local = serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"temp"}});
        let declaration = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
        "file":"code/test.dm","line":4,"fields":{
            "Name":"temp","Type":null,"ValueType":null,"IsGlobal":false,
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"rate"}}
        }});
        let write = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":6,"fields":{"Expression":{
            "kind":"DMASTAssign","file":"code/test.dm","line":6,"fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"result"}},
                "RHS":local.clone()
            }}}});
        let guarded = serde_json::json!({"kind":"DMASTProcStatementIf",
        "file":"code/test.dm","line":5,"fields":{
            "Condition":{"kind":"DMASTNotEqual","fields":{
                "LHS":local,"RHS":{"kind":"DMASTConstantNull"}}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[write]}},
            "ElseBody":null
        }});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":3,
            "parameters":[{"Name":"rate","type":null,"valueType":null,"defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[declaration,guarded]}}});
        let source = format!("{field}\n{proc}\n");
        let contracts = crate::contracts::collect(
            "// dm-health: type num?\n/datum/test/var/result\n\
             // dm-health: param rate num?\n/datum/test/proc/Run(rate)\n",
        );
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-field-write"
                && finding.message.contains("result")));
    }

    #[test]
    fn field_write_evidence_preserves_unwritten_parameter_across_branch() {
        let field = serde_json::json!({"kind":"field","owner":"/datum",
            "name":"mark","file":"code/test.dm","line":1,
            "type":null,"valueType":"\"anything\"","initializer":null});
        let receiver = serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"D"}});
        let lhs = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":receiver,"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"mark"}}]}});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":5,"fields":{"Expression":{
                "kind":"DMASTAssign","fields":{"LHS":lhs,
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":4}}}}}});
        let branch = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
            "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementReturn","fields":{"Value":null}}]}},
            "ElseBody":null}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/worker","name":"Run",
            "file":"code/test.dm","line":2,
            "parameters":[{"Name":"D","type":"/datum","valueType":null,"defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[branch,assignment]}}});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-field-type"
                && finding.message.contains("/datum.mark")));

        let mut changed = proc;
        changed["body"]["fields"]["Statements"][0]["fields"]["Body"]["fields"]["Statements"] = serde_json::json!([{"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"D"}},
                "RHS":{"kind":"DMASTConstantString","fields":{"Value":"other"}}}}
        }}]);
        let source = format!("{field}\n{changed}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-field-type"
                && finding.message.contains("/datum.mark")));
    }

    #[test]
    fn nullable_assignment_preserves_subtype_compatibility() {
        let symbols = Symbols::default();
        let expected = Ty::Nullable(Box::new(Ty::Path("/datum".into())));
        let child = Ty::Path("/datum/child".into());
        assert!(expected.accepts(&Ty::Null, &symbols));
        assert!(expected.accepts(&child, &symbols));
        assert!(expected.accepts(&Ty::Nullable(Box::new(child)), &symbols));
        assert!(!Ty::Path("/datum".into()).accepts(&expected, &symbols));
        assert!(!expected.accepts(&Ty::Nullable(Box::new(Ty::Text)), &symbols));
    }

    #[test]
    fn proc_shards_reuse_unchanged_body_after_another_body_changes() {
        let directory = std::env::temp_dir().join(format!(
            "dm-health-proc-shards-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let make_proc = |name: &str, value: i64| {
            serde_json::json!({"kind":"proc","owner":"/datum/test","name":name,
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":2,
                    "fields":{"Value":{"kind":"DMASTConstantInteger","fields":{"Value":value}}}
                }]}
            }})
        };
        let run = |first_value| {
            let source = format!(
                "{}\n{}\n",
                make_proc("First", first_value),
                make_proc("Second", 2)
            );
            analyze_with_cache(
                source.as_bytes(),
                Cursor::new(source.as_bytes()),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
                Some(&directory),
            )
            .unwrap()
        };
        let (first_findings, first) = run(1);
        assert_eq!(first.checked_procs_recomputed, 2);
        assert_eq!(first.checked_procs_reused, 0);
        let (second_findings, second) = run(1);
        assert_eq!(first_findings, second_findings);
        assert_eq!(second.checked_procs_recomputed, 0);
        assert_eq!(second.checked_procs_reused, 2);
        assert_eq!(first.typed_expressions, second.typed_expressions);
        let (_, changed) = run(3);
        assert_eq!(changed.checked_procs_recomputed, 1);
        assert_eq!(changed.checked_procs_reused, 1);
        let mut second = make_proc("Second", 2);
        second["body"]["fields"]["Statements"][0]["fields"]["Value"] =
            serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"two"}});
        let changed_signature = format!("{}\n{}\n", make_proc("First", 3), second);
        let (_, invalidated) = analyze_with_cache(
            changed_signature.as_bytes(),
            Cursor::new(changed_signature.as_bytes()),
            changed_signature.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
            Some(&directory),
        )
        .unwrap();
        assert_eq!(invalidated.checked_procs_recomputed, 2);
        assert_eq!(invalidated.checked_procs_reused, 0);
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn proc_shard_rejects_corrupt_single_file_envelope() {
        let directory = std::env::temp_dir().join(format!(
            "dm-health-proc-envelope-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&directory).unwrap();
        store_proc_shard(&directory, "test", &[], &TypeCoverage::default()).unwrap();
        assert!(load_proc_shard(&directory, "test").is_some());
        assert_eq!(fs::read_dir(&directory).unwrap().count(), 1);
        let path = directory.join("test.shard");
        let mut bytes = fs::read(&path).unwrap();
        bytes[0] ^= 1;
        fs::write(&path, bytes).unwrap();
        assert!(load_proc_shard(&directory, "test").is_none());
        // A corrupt entry must be replaceable after the failed cache read.
        store_proc_shard(&directory, "test", &[], &TypeCoverage::default()).unwrap();
        assert!(load_proc_shard(&directory, "test").is_some());
        fs::remove_dir_all(directory).unwrap();
    }

    #[test]
    fn unsupported_switch_invalidates_following_flow_facts() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementSwitch","file":"code/test.dm","line":2,
                    "fields":{}},
                {"kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                    "fields":{"Expression":{"kind":"DMASTDereference",
                        "file":"code/test.dm","line":3,"fields":{
                            "Expression":{"kind":"DMASTIdentifier","fields":{
                                "Identifier":"src"}},
                            "Operations":[{"kind":"FieldOperation","fields":{
                                "Identifier":"name","Safe":false}}]}}}}
            ]}}});
        let source = proc.to_string();
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(coverage.unverified_control_flow, 1);
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-control-flow"));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference" && finding.line == 3));
    }

    #[test]
    fn unlabeled_loop_jumps_skip_the_rest_of_the_iteration() {
        for jump in ["DMASTProcStatementBreak", "DMASTProcStatementContinue"] {
            let access = serde_json::json!({"kind":"DMASTProcStatementExpression",
                "file":"code/test.dm","line":4,"fields":{"Expression":{
                    "kind":"DMASTDereference","file":"code/test.dm","line":4,
                    "fields":{"Expression":{"kind":"DMASTIdentifier","fields":{
                        "Identifier":"item"}},"Operations":[{"kind":"FieldOperation",
                        "fields":{"Identifier":"name","Safe":false}}]}}}});
            let loop_body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
                "Statements":[{"kind":jump,"file":"code/test.dm","line":3,
                    "fields":{"Label":null}},access]}});
            let iteration = serde_json::json!({"kind":"DMASTProcStatementWhile",
                "file":"code/test.dm","line":2,"fields":{
                    "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                    "Body":loop_body}});
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
                "file":"code/test.dm","line":1,"parameters":[{"Name":"item",
                    "type":"/datum/test","valueType":null,"defaultValue":null}],"body":{
                    "kind":"DMASTProcBlockInner","fields":{"Statements":[iteration]}}});
            let source = proc.to_string();
            let (findings, coverage) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(coverage.unverified_control_flow, 0, "{jump}");
            assert!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "strict-null-dereference" && finding.line == 4),
                "{jump}"
            );
        }
    }

    #[test]
    fn loop_conditions_are_checked_at_their_actual_phase() {
        let condition = serde_json::json!({"kind":"DMASTDereference",
            "file":"code/test.dm","line":3,"fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                "Operations":[{"kind":"FieldOperation","fields":{
                    "Identifier":"name","Safe":false}}]}});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":2,"fields":{"Expression":{
                "kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                    "RHS":{"kind":"DMASTNewPath","fields":{"Path":{
                        "kind":"DMASTConstantPath","fields":{"Value":{
                            "kind":"DMASTPath","fields":{"Path":"/datum/test"}}}}}}}}}});
        for loop_kind in ["DMASTProcStatementWhile", "DMASTProcStatementDoWhile"] {
            let mut iteration = serde_json::json!({"kind":loop_kind,"file":"code/test.dm",
                "line":2,"fields":{"Conditional":condition,"Body":{
                    "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}}});
            let make_proc = |iteration: &Value| {
                serde_json::json!({"kind":"proc",
                "owner":"/datum/test","name":"Run","file":"code/test.dm","line":1,
                "parameters":[{"Name":"item","type":"/datum/test","valueType":null,
                    "defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
                    "fields":{"Statements":[iteration]}}})
            };
            let check = |iteration: &Value| {
                let source = make_proc(iteration).to_string();
                analyze(
                    source.as_bytes(),
                    source.as_bytes(),
                    source.as_bytes(),
                    &Symbols::default(),
                    &[],
                    &Selection {
                        all: true,
                        ..Selection::default()
                    },
                )
                .unwrap()
                .0
            };
            assert!(
                check(&iteration)
                    .iter()
                    .any(|finding| finding.rule == "strict-null-dereference" && finding.line == 3),
                "{loop_kind}"
            );
            if loop_kind == "DMASTProcStatementDoWhile" {
                iteration["fields"]["Body"]["fields"]["Statements"] =
                    serde_json::json!([assignment]);
                assert!(!check(&iteration)
                    .iter()
                    .any(|finding| finding.rule == "strict-null-dereference" && finding.line == 3));
            }
        }
    }

    #[test]
    fn changing_loop_fact_converges_to_nullable() {
        let contracts =
            crate::contracts::collect("// dm-health: nullable(item)\n/datum/test/proc/Run(item)\n");
        let assigned = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":2,"fields":{"Expression":{
                "kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                    "RHS":{"kind":"DMASTNewPath","fields":{"Path":{
                        "kind":"DMASTConstantPath","fields":{"Value":{
                            "kind":"DMASTPath","fields":{"Path":"/datum/test"}}}}}}}}}});
        let cleared = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":4,"fields":{"Expression":{
                "kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                    "RHS":{"kind":"DMASTConstantNull","fields":{}}}}}});
        let iteration = serde_json::json!({"kind":"DMASTProcStatementWhile",
            "file":"code/test.dm","line":3,"fields":{
                "Conditional":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[cleared]}}}});
        let access = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":5,"fields":{"Expression":{
                "kind":"DMASTDereference","file":"code/test.dm","line":5,"fields":{
                    "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                    "Operations":[{"kind":"FieldOperation","fields":{
                        "Identifier":"name","Safe":false}}]}}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"item",
                "type":"/datum/test","valueType":null,"defaultValue":null}],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[assigned,iteration,access]}}});
        let source = proc.to_string();
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(coverage.unverified_control_flow, 0);
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unverified-loop-fixed-point"));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference" && finding.line == 5));
    }

    #[test]
    fn switch_joins_all_case_assignments_and_unmatched_path() {
        let contracts =
            crate::contracts::collect("// dm-health: returns num\n/datum/test/proc/Run()\n");
        let assign = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":4,"fields":{"Expression":{
                "kind":"DMASTAssign","file":"code/test.dm","line":4,"fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":2}}}}}});
        let mut proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementVarDeclaration","file":"code/test.dm",
                    "line":2,"fields":{"Name":"value","Type":"/num",
                        "ValueType":"num","Value":null}},
                {"kind":"DMASTProcStatementSwitch","file":"code/test.dm","line":3,
                    "fields":{"Value":{"kind":"DMASTConstantInteger",
                        "fields":{"Value":1}},"Cases":[
                        {"kind":"SwitchCaseValues","fields":{"Values":[{
                            "kind":"DMASTConstantInteger","fields":{"Value":1}}],
                            "Body":{"kind":"DMASTProcBlockInner","fields":{
                                "Statements":[assign]}}}},
                        {"kind":"SwitchCaseDefault","fields":{"Body":{
                            "kind":"DMASTProcBlockInner","fields":{"Statements":[assign]}}}}
                    ]}},
                {"kind":"DMASTProcStatementReturn","file":"code/test.dm","line":5,
                    "fields":{"Value":{"kind":"DMASTIdentifier","fields":{
                        "Identifier":"value"}}}}
            ]}}});
        let check = |proc: &Value| {
            let source = proc.to_string();
            analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
        };
        let (findings, coverage) = check(&proc);
        assert_eq!(coverage.unverified_control_flow, 0);
        assert!(!findings.iter().any(|finding| matches!(
            finding.rule,
            "read-before-assignment" | "strict-type-assignment" | "unknown-type-flow"
        )));
        proc["body"]["fields"]["Statements"][1]["fields"]["Cases"]
            .as_array_mut()
            .unwrap()
            .pop();
        let (findings, _) = check(&proc);
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "read-before-assignment"
                || finding.rule == "strict-type-assignment"));
    }

    #[test]
    fn return_inference_checks_switch_default_path() {
        let returned = serde_json::json!({"kind":"DMASTProcStatementReturn",
            "file":"code/test.dm","line":3,"fields":{"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        let mut proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Choose",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementSwitch","file":"code/test.dm","line":2,
                "fields":{"Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "Cases":[
                    {"kind":"SwitchCaseValues","fields":{"Values":[{
                        "kind":"DMASTConstantInteger","fields":{"Value":1}}],
                        "Body":{"kind":"DMASTProcBlockInner","fields":{
                            "Statements":[returned]}}}},
                    {"kind":"SwitchCaseDefault","fields":{"Body":{
                        "kind":"DMASTProcBlockInner","fields":{"Statements":[returned]}}}}
                ]}}]}}});
        let check = |proc: &Value| {
            let source = proc.to_string();
            analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
            .0
        };
        assert!(!check(&proc)
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"));
        proc["body"]["fields"]["Statements"][0]["fields"]["Cases"]
            .as_array_mut()
            .unwrap()
            .pop();
        assert!(check(&proc)
            .iter()
            .any(|finding| finding.rule == "unannotated-nullable-return"));
    }

    #[test]
    fn typed_parameter_needs_an_entry_guard_before_dereference() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"name",
            "file":"code/test.dm","line":1,"type":"/text","valueType":"text",
            "initializer":{"kind":"DMASTConstantString","fields":{"Value":"test"}}});
        let access = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":3,"fields":{"Expression":{
                "kind":"DMASTDereference","file":"code/test.dm","line":3,"fields":{
                    "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                    "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"name",
                        "Safe":false}}]}}}});
        let mut proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[{"Name":"item",
                "type":"/datum/test","valueType":null,"defaultValue":null}],"body":{
                    "kind":"DMASTProcBlockInner","fields":{"Statements":[access]}}});
        let check = |proc: &Value| {
            let source = format!("{field}\n{proc}\n");
            analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
            .0
        };
        assert!(check(&proc)
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));
        let access = proc["body"]["fields"]["Statements"][0].clone();
        proc["body"]["fields"]["Statements"] = serde_json::json!([{
            "kind":"DMASTProcStatementIf","file":"code/test.dm","line":3,"fields":{
                "Condition":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[access]}}}}]);
        assert!(!check(&proc)
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));

        let access = proc["body"]["fields"]["Statements"][0]["fields"]["Body"]["fields"]
            ["Statements"][0]
            .clone();
        proc["body"]["fields"]["Statements"] = serde_json::json!([
            {"kind":"DMASTProcStatementIf","file":"code/test.dm","line":3,"fields":{
                "Condition":{"kind":"DMASTNot","fields":{"Value":{
                    "kind":"DMASTIdentifier","fields":{"Identifier":"item"}}}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementReturn","fields":{"Value":null}}]}}}},
            access
        ]);
        assert!(!check(&proc)
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));
    }

    #[test]
    fn unguarded_typed_parameter_does_not_prove_nonnull_return() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Forward",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"item",
                "type":"/datum/test","valueType":null,"defaultValue":null}],"body":{
                    "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                        "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":2,
                        "fields":{"Value":{"kind":"DMASTIdentifier","fields":{
                            "Identifier":"item"}}}}]}}});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unannotated-nullable-return"));
    }

    #[test]
    fn uninitialized_typed_local_does_not_prove_nonnull_return() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Forward",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementVarDeclaration","file":"code/test.dm",
                    "line":2,"fields":{"Name":"item","Type":"/datum/test",
                        "ValueType":null,"Value":null}},
                {"kind":"DMASTProcStatementReturn","file":"code/test.dm","line":3,
                    "fields":{"Value":{"kind":"DMASTIdentifier","fields":{
                        "Identifier":"item"}}}}
            ]}}});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"));
    }

    #[test]
    fn length_and_prob_have_numeric_result_types() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementExpression","file":"code/test.dm","line":2,
                    "fields":{"Expression":{"kind":"DMASTLength","file":"code/test.dm",
                        "line":2,"fields":{"Value":{"kind":"DMASTConstantString",
                            "fields":{"Value":"abc"}}}}}},
                {"kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                    "fields":{"Expression":{"kind":"DMASTProb","file":"code/test.dm",
                        "line":3,"fields":{"Value":{"kind":"DMASTConstantInteger",
                            "fields":{"Value":50}}}}}}
            ]}}});
        let source = proc.to_string();
        let (_, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(coverage.unresolved_by_kind.get("DMASTLength"), None);
        assert_eq!(coverage.unresolved_by_kind.get("DMASTProb"), None);
    }

    #[test]
    fn static_proc_reference_call_checks_its_arguments() {
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Take",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"amount","type":null,
            "valueType":"num","defaultValue":null}],"body":null});
        let call = serde_json::json!({"kind":"DMASTCall","file":"code/test.dm","line":3,
            "fields":{"CallParameters":[{"kind":"DMASTCallParameter","fields":{
                "Value":{"kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/datum/test/proc/Take"}}}},"Key":null}}],
                "ProcParameters":[{"kind":"DMASTCallParameter","fields":{
                    "Value":{"kind":"DMASTConstantString","fields":{"Value":"wrong"}},"Key":null}}]}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                    "fields":{"Expression":call}}]}}});
        let source = format!("{target}\n{caller}\n");
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(coverage.resolved_calls > 0);
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unresolved-dynamic-call"));

        let mut computed_caller = caller;
        computed_caller["body"]["fields"]["Statements"][0]["fields"]["Expression"]["fields"]
            ["CallParameters"][0]["fields"]["Value"] = serde_json::json!({
            "kind":"DMASTIdentifier","fields":{"Identifier":"reference"}});
        let computed_source = format!("{target}\n{computed_caller}\n");
        let (computed_findings, _) = analyze(
            computed_source.as_bytes(),
            computed_source.as_bytes(),
            computed_source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(computed_findings
            .iter()
            .any(|finding| finding.rule == "unresolved-dynamic-call"));
    }

    #[test]
    fn finite_literal_dynamic_names_require_matching_signatures() {
        let target = |name: &str, value_type: &str| {
            serde_json::json!({"kind":"proc","owner":"/datum/test","name":name,
                "file":"code/test.dm","line":1,"parameters":[{"Name":"amount","type":null,
                "valueType":value_type,"defaultValue":null}],"body":null})
        };
        let call = serde_json::json!({"kind":"DMASTCall","file":"code/test.dm","line":4,
            "fields":{"CallParameters":[
                {"kind":"DMASTCallParameter","fields":{"Value":{"kind":"DMASTIdentifier",
                    "fields":{"Identifier":"src"}},"Key":null}},
                {"kind":"DMASTCallParameter","fields":{"Value":{"kind":"DMASTTernary",
                    "fields":{"A":{"kind":"DMASTIdentifier","fields":{"Identifier":"choice"}},
                        "B":{"kind":"DMASTConstantString","fields":{"Value":"TakeA"}},
                        "C":{"kind":"DMASTConstantString","fields":{"Value":"TakeB"}}}},
                    "Key":null}}],
                "ProcParameters":[{"kind":"DMASTCallParameter","fields":{
                    "Value":{"kind":"DMASTConstantString","fields":{"Value":"wrong"}},"Key":null}}]}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":3,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":4,
                    "fields":{"Expression":call}}]}}});
        let check = |second_type: &str| {
            let source = format!(
                "{}\n{}\n{}\n",
                target("TakeA", "num"),
                target("TakeB", second_type),
                caller
            );
            analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
            .0
        };
        let matching = check("num");
        assert!(matching
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"));
        assert!(!matching
            .iter()
            .any(|finding| finding.rule == "unresolved-dynamic-call"));
        let different = check("text");
        assert!(different
            .iter()
            .any(|finding| finding.rule == "unresolved-dynamic-call"));
    }

    #[test]
    fn nullable_dynamic_receiver_is_not_resolved_as_safe() {
        let contracts = crate::contracts::collect(
            "// dm-health: nullable\n/datum/test/var/datum/test/target\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"target",
            "file":"code/test.dm","line":1,"type":"/datum/test","valueType":null,
            "initializer":null});
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Take",
            "file":"code/test.dm","line":2,"parameters":[],"body":null});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":3,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":4,
                    "fields":{"Expression":{"kind":"DMASTCall","file":"code/test.dm","line":4,
                        "fields":{"CallParameters":[
                            {"kind":"DMASTCallParameter","fields":{"Value":{
                                "kind":"DMASTIdentifier","fields":{"Identifier":"target"}},"Key":null}},
                            {"kind":"DMASTCallParameter","fields":{"Value":{
                                "kind":"DMASTConstantString","fields":{"Value":"Take"}},"Key":null}}],
                            "ProcParameters":[]}}}}]}}});
        let source = format!("{field}\n{target}\n{caller}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"
                && finding.message.contains("dynamic call receiver")));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unresolved-dynamic-call"));

        let mut guarded = caller;
        let call_statement = guarded["body"]["fields"]["Statements"][0].clone();
        guarded["body"]["fields"]["Statements"] = serde_json::json!([{
        "kind":"DMASTProcStatementIf","file":"code/test.dm","line":4,"fields":{
            "Condition":{"kind":"DMASTIdentifier","file":"code/test.dm","line":4,
                "fields":{"Identifier":"target"}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[call_statement]}}
        }}]);
        let guarded_source = format!("{field}\n{target}\n{guarded}\n");
        let (guarded_findings, _) = analyze(
            guarded_source.as_bytes(),
            guarded_source.as_bytes(),
            guarded_source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!guarded_findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"
                || finding.rule == "unresolved-dynamic-call"));
    }

    #[test]
    fn unknown_call_invalidates_bare_field_guard_but_preserves_local() {
        let mut env = Env::default();
        env.slots.insert("local".into(), Ty::Num);
        env.facts.insert("local".into(), Ty::Num);
        env.slots
            .insert("items".into(), Ty::parse("list</obj/item>"));
        env.facts
            .insert("items".into(), Ty::parse("list</obj/item>"));
        env.facts.insert("field".into(), Ty::Num);
        env.facts
            .insert("src".into(), Ty::Path("/datum/test".into()));
        let call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Unknown"}},
            "Parameters":[]
        }});
        env.invalidate_after(&call);
        assert_eq!(env.facts.get("local"), Some(&Ty::Num));
        assert_eq!(env.facts.get("items"), Some(&Ty::Unknown));
        assert!(!env.facts.contains_key("field"));
        assert_eq!(env.facts.get("src"), Some(&Ty::parse("/datum/test?")));
        let mut result = Ty::parse("list</obj/item>");
        invalidate_result_after(&call, &mut result);
        assert_eq!(result, Ty::Unknown);
        assert_eq!(
            stale_after_unknown_effect(&Ty::parse("list</obj/item>?")),
            Ty::Unknown
        );
    }

    #[test]
    fn effect_in_left_operand_invalidates_right_operand_null_fact() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let mut env = Env::default();
        env.slots.insert("item".into(), Ty::parse("/datum/test?"));
        env.facts
            .insert("item".into(), Ty::Path("/datum/test".into()));
        env.assigned.insert("item".into());
        let expression = serde_json::json!({"kind":"DMASTAdd",
            "file":"code/test.dm","line":2,"fields":{
            "LHS":{"kind":"DMASTProcCall","file":"code/test.dm","line":2,
                "fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                    "fields":{"Identifier":"Mutate"}},"Parameters":[]}},
            "RHS":{"kind":"DMASTDereference","file":"code/test.dm","line":2,
                "fields":{"Expression":{"kind":"DMASTIdentifier",
                    "fields":{"Identifier":"item"}},
                    "Operations":[{"kind":"FieldOperation","fields":{
                        "Identifier":"name","Safe":false}}]}}
        }});
        checker.inspect_expr(&expression, "/datum/test", &env);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"
                && finding.message.contains("receiver may be null")));

        let signature = Signature {
            parameters: vec![
                ParamInfo {
                    name: "change".into(),
                    ty: Ty::Unknown,
                    has_default: false,
                    default_ty: Ty::Unknown,
                    inferred_from_calls: false,
                },
                ParamInfo {
                    name: "item".into(),
                    ty: Ty::Path("/datum/test".into()),
                    has_default: false,
                    default_ty: Ty::Unknown,
                    inferred_from_calls: false,
                },
            ],
            result: Ty::Void,
            result_required: false,
            inferred_nullable_result: false,
            path: "code/test.dm".into(),
            line: 1,
        };
        let call = serde_json::json!({"kind":"DMASTProcCall",
        "file":"code/test.dm","line":3,"fields":{
        "Parameters":[
            {"kind":"DMASTCallParameter","file":"code/test.dm","line":3,
                "fields":{"Key":null,"Value":expression["fields"]["LHS"]}},
            {"kind":"DMASTCallParameter","file":"code/test.dm","line":3,
                "fields":{"Key":null,"Value":{"kind":"DMASTIdentifier",
                    "fields":{"Identifier":"item"}}}}
        ]}});
        checker.check_arguments(&call, &signature, "/datum/test", &env.facts, "Parameters");
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("argument item")));
        let mut dereference_call = call;
        dereference_call["fields"]["Parameters"][1]["fields"]["Value"] =
            expression["fields"]["RHS"].clone();
        let before = checker
            .findings
            .iter()
            .filter(|finding| finding.rule == "strict-null-dereference")
            .count();
        checker.inspect_expr(&dereference_call, "/datum/test", &env);
        assert!(
            checker
                .findings
                .iter()
                .filter(|finding| finding.rule == "strict-null-dereference")
                .count()
                > before
        );
    }

    #[test]
    fn condition_call_does_not_reestablish_earlier_field_guard() {
        let contracts =
            crate::contracts::collect("// dm-health: nullable\n/datum/test/var/obj/item/field\n");
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"field",
            "file":"code/test.dm","line":1,"type":"/obj/item","valueType":"\"anything\"",
            "initializer":{"kind":"DMASTConstantNull","fields":{}}});
        let guarded = serde_json::json!({"kind":"DMASTProcStatementIf","file":"code/test.dm","line":3,"fields":{
            "Condition":{"kind":"DMASTAnd","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"field"}},
                "RHS":{"kind":"DMASTProcCall","fields":{"Callable":{
                    "kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Unknown"}},"Parameters":[]}}
            }},"Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":4,
                "fields":{"Expression":{"kind":"DMASTDereference","file":"code/test.dm","line":4,
                    "fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"field"}},
                        "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"name","Safe":false}}]}}}
            }]}}
        }});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":2,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[guarded]}
        }});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference" && finding.line == 4));
    }

    #[test]
    fn bare_field_names_resolve_and_check_writes() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"count",
            "file":"code/test.dm","line":1,"type":"/num","valueType":"\"num\"",
            "initializer":{"kind":"DMASTConstantInteger","fields":{"Value":1}}});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":3,"fields":{"Expression":{
            "kind":"DMASTAssign","file":"code/test.dm","line":3,"fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"count"}},
                "RHS":{"kind":"DMASTConstantString","fields":{"Value":"bad"}}
            }
        }}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":2,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[assignment]}
        }});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("count")));
    }

    #[test]
    fn bare_field_write_infers_storage_but_local_shadow_does_not() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"count",
            "file":"code/test.dm","line":1,"type":null,"valueType":"\"anything\"",
            "initializer":{"kind":"DMASTConstantNull","fields":{}}});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":3,"fields":{"Expression":{
            "kind":"DMASTAssign","file":"code/test.dm","line":3,"fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"count"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
            }
        }}});
        for shadow in [false, true] {
            let mut statements = Vec::new();
            if shadow {
                statements.push(
                    serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
                    "fields":{"Name":"count","Type":null,"ValueType":"\"anything\"",
                        "Value":{"kind":"DMASTConstantNull","fields":{}}}}),
                );
            }
            statements.push(assignment.clone());
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":statements}
            }});
            let source = format!("{field}\n{proc}\n");
            let (findings, _) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "unknown-field-type"),
                shadow
            );
        }
    }

    #[test]
    fn null_initializer_is_not_a_storage_type() {
        let field = serde_json::json!({"kind":"field","owner":"/obj","name":"name",
            "file":"code/test.dm","line":1,"type":null,"valueType":"\"anything\"",
            "initializer":{"kind":"DMASTConstantNull","fields":{}}});
        let source = field.to_string();
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(coverage.unresolved_declarations, 1);
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-field-type"));
    }

    #[test]
    fn numeric_range_loop_binds_untyped_iterator_as_number() {
        let iterator = serde_json::json!({"kind":"DMASTExpressionInRange","fields":{
            "Value":{"kind":"DMASTVarDeclExpression","fields":{
                "DeclPath":{"kind":"DMASTPath","fields":{"Path":"var/i"}}}},
            "StartRange":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "EndRange":{"kind":"DMASTConstantInteger","fields":{"Value":3}},
            "Step":null}});
        let body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementVarDeclaration","file":"code/test.dm","line":3,
                "fields":{"Name":"n","Type":"/num","ValueType":"num",
                    "Value":{"kind":"DMASTIdentifier","file":"code/test.dm","line":3,
                        "fields":{"Identifier":"i"}},"IsGlobal":false}}
        ]}});
        let loop_statement = serde_json::json!({"kind":"DMASTProcStatementFor",
            "file":"code/test.dm","line":2,"fields":{"Expression1":iterator,
                "Expression2":null,"Expression3":null,"DMTypes":null,"Body":body}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":1,"parameters":[],"returnType":null,
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[loop_statement]}}});
        let source = format!("{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unverified-control-flow"
                    || finding.rule == "unknown-type-flow" && finding.path == "code/test.dm"),
            "{findings:?}"
        );
    }

    #[test]
    fn global_namespace_resolves_root_fields() {
        let field = serde_json::json!({"kind":"field","owner":"/","name":"config",
            "file":"code/test.dm","line":1,"type":"/datum/controller/configuration",
            "valueType":null,"initializer":{"kind":"DMASTNewInferred","fields":{"Parameters":null}}});
        let lookup = serde_json::json!({"kind":"DMASTDereference","file":"code/test.dm",
        "line":3,"fields":{"Expression":{"kind":"DMASTIdentifier",
            "fields":{"Identifier":"global"}},"Operations":[
                {"kind":"FieldOperation","fields":{"Identifier":"config","Conditional":false}}
            ]}});
        let body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementVarDeclaration","file":"code/test.dm","line":3,
                "fields":{"Name":"chosen","Type":"/datum/controller/configuration",
                    "ValueType":null,"Value":lookup,"IsGlobal":false}}
        ]}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[],"body":body});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-type-flow" && finding.line == 3),
            "{findings:?}"
        );
    }

    #[test]
    fn iterator_declaration_reads_typed_ast_path() {
        let declaration = serde_json::json!({"kind":"DMASTVarDeclExpression","fields":{
            "DeclPath":{"kind":"DMASTPath","fields":{"Path":"var/datum/affliction_trigger/injury/c"}}
        }});
        assert_eq!(
            iterator_declaration(&declaration),
            Some((
                "c".into(),
                Ty::Path("/datum/affliction_trigger/injury".into())
            ))
        );
    }

    #[test]
    fn loop_element_is_checked_against_declared_variable_type() {
        let iteration = serde_json::json!({"kind":"DMASTProcStatementFor","file":"code/test.dm","line":2,"fields":{
            "DMTypes":"\"anything\"",
            "Expression1":{"kind":"DMASTExpressionIn","file":"code/test.dm","line":2,"fields":{
                "LHS":{"kind":"DMASTVarDeclExpression","fields":{"DeclPath":{"kind":"DMASTPath","fields":{"Path":"var/num/value"}}}},
                "RHS":{"kind":"DMASTList","fields":{"Values":[{"kind":"DMASTCallParameter","fields":{
                    "Key":null,"Value":{"kind":"DMASTConstantString","fields":{"Value":"bad"}}
                }}]}}
            }},"Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}
        }});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[iteration]}
        }});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("value")));
        let mut filtered_proc = proc;
        filtered_proc["body"]["fields"]["Statements"][0]["fields"]["DMTypes"] = Value::Null;
        let filtered_source = filtered_proc.to_string();
        let (filtered_findings, _) = analyze(
            filtered_source.as_bytes(),
            filtered_source.as_bytes(),
            filtered_source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!filtered_findings.iter().any(|finding| {
            finding.rule == "strict-type-assignment"
                || finding.rule == "unverified-iterator-element"
        }));
    }

    #[test]
    fn contradictory_field_and_parameter_contracts_are_errors() {
        let symbols = Symbols::default();
        let contracts = crate::contracts::collect(
            "// dm-health: nullable\n// dm-health: initialized-by New\n// dm-health: initialized-by Initialize\n// dm-health: type num?\n// dm-health: nonnull\n/datum/test/var/number\n\n// dm-health: param value num\n// dm-health: param value text\n/datum/test/proc/set(value)\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"number",
            "file":"code/test.dm","line":5,"type":"num","valueType":"num","initializer":null});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"set",
            "file":"code/test.dm","line":9,"parameters":[{"Name":"value","type":null,"valueType":null,"defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let source = format!("{}\n{}\n", field, proc);
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &symbols,
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        let conflicts: Vec<_> = findings
            .iter()
            .filter(|finding| finding.rule == "conflicting-type-contract")
            .collect();
        assert!(conflicts
            .iter()
            .any(|finding| finding.message.contains("nonnull conflicts with nullable")));
        assert!(conflicts.iter().any(|finding| finding
            .message
            .contains("initialized-by conflicts with nullable")));
        assert!(conflicts.iter().any(|finding| finding
            .message
            .contains("multiple different initialized-by phases")));
        assert!(conflicts.iter().any(|finding| finding
            .message
            .contains("multiple different type contracts")));
    }

    #[test]
    fn initialized_by_new_requires_a_single_direct_literal_assignment() {
        let symbols = Symbols::default();
        let contracts =
            crate::contracts::collect("// dm-health: initialized-by New\n/datum/test/var/number\n");
        assert!(contracts
            .iter()
            .any(|contract| contract.visibility == Visibility::InitializedBy));
        let field = serde_json::json!({"kind":"field","owner":"/datum/test", "name":"number",
            "file":"code/test.dm","line":2,"type":"num","valueType":"num","initializer":null});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"number"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
            }}
        }});
        let new_proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"New",
        "file":"code/test.dm","line":3,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[assignment]}
        }});
        let source = format!("{}\n{}\n", field, new_proc);
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &symbols,
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "required-field-uninitialized"));

        let atom_contracts =
            crate::contracts::collect("// dm-health: initialized-by New\n/obj/test/var/number\n");
        let mut atom_field = field.clone();
        atom_field["owner"] = Value::String("/obj/test".into());
        let mut atom_new = new_proc.clone();
        atom_new["owner"] = Value::String("/obj/test".into());
        let atom_source = format!("{}\n{}\n", atom_field, atom_new);
        let (atom_findings, _) = analyze(
            atom_source.as_bytes(),
            atom_source.as_bytes(),
            atom_source.as_bytes(),
            &symbols,
            &atom_contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(atom_findings
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"
                && finding.message.contains("atom New")));
        let initialize_contracts = crate::contracts::collect(
            "// dm-health: initialized-by Initialize\n/obj/test/var/number\n",
        );
        let (initialize_findings, _) = analyze(
            atom_source.as_bytes(),
            atom_source.as_bytes(),
            atom_source.as_bytes(),
            &symbols,
            &initialize_contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(initialize_findings.iter().any(|finding| {
            finding.rule == "unproven-initialization"
                && finding.message.contains("deferred during map loading")
        }));

        let early_call = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTProcCall","fields":{}}
        }});
        let mut unsafe_proc = new_proc;
        unsafe_proc["body"]["fields"]["Statements"]
            .as_array_mut()
            .unwrap()
            .insert(0, early_call);
        let unsafe_source = format!("{}\n{}\n", field, unsafe_proc);
        let (unsafe_findings, _) = analyze(
            unsafe_source.as_bytes(),
            unsafe_source.as_bytes(),
            unsafe_source.as_bytes(),
            &symbols,
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(unsafe_findings
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"));
    }

    #[test]
    fn simple_new_initialization_needs_no_annotation_but_later_null_write_fails() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"number",
            "file":"code/test.dm","line":1,"type":"/num","valueType":"num","initializer":null});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","file":"code/test.dm","line":3,"fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"number"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}}});
        let new_proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"New",
            "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[assignment]}}});
        let source = format!("{field}\n{new_proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "required-field-uninitialized"
                && finding.message.contains("number")));

        let clear = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Clear",
            "file":"code/test.dm","line":4,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{
                "Expression":{"kind":"DMASTAssign","file":"code/test.dm","line":5,"fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"number"}},
                    "RHS":{"kind":"DMASTConstantNull","fields":{}}}}}}]}}});
        let source_with_clear = format!("{source}{clear}\n");
        let (findings, _) = analyze(
            source_with_clear.as_bytes(),
            source_with_clear.as_bytes(),
            source_with_clear.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("number")));
    }

    #[test]
    fn initialized_by_new_requires_every_branch_and_allows_literal_sibling() {
        let contracts =
            crate::contracts::collect("// dm-health: initialized-by New\n/datum/test/var/number\n");
        let required = serde_json::json!({"kind":"field","owner":"/datum/test","name":"number",
            "file":"code/test.dm","line":1,"type":"num","valueType":"num","initializer":null});
        let sibling = serde_json::json!({"kind":"field","owner":"/datum/test","name":"other",
            "file":"code/test.dm","line":2,"type":"num","valueType":"num",
            "initializer":{"kind":"DMASTConstantInteger","fields":{"Value":2}}});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"number"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}}});
        let branch = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
            "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[assignment]}},
            "ElseBody":{"kind":"DMASTProcBlockInner","fields":{"Statements":[assignment]}}}});
        let mut new_proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"New",
            "file":"code/test.dm","line":3,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[branch]}}});
        let source = format!("{required}\n{sibling}\n{new_proc}\n");
        let check = |input: &str| {
            analyze(
                input.as_bytes(),
                input.as_bytes(),
                input.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
            .0
        };
        assert!(!check(&source)
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"));
        new_proc["body"]["fields"]["Statements"][0]["fields"]["ElseBody"] = Value::Null;
        let missing = format!("{required}\n{sibling}\n{new_proc}\n");
        assert!(check(&missing)
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"));

        let inherited = serde_json::json!({"kind":"proc","owner":"/datum","name":"New",
            "file":"code/test.dm","line":5,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let inherited_source = format!("{inherited}\n{source}");
        assert!(check(&inherited_source)
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"));
    }

    #[test]
    fn initialized_by_new_accepts_a_compatible_literal_typepath() {
        let contracts = crate::contracts::collect(
            "// dm-health: initialized-by New\n// dm-health: type typepath</datum>\n/datum/test/var/chosen_type\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test",
            "name":"chosen_type","file":"code/test.dm","line":1,
            "type":null,"valueType":null,"initializer":null});
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "fields":{"Expression":{"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"chosen_type"}},
            "RHS":{"kind":"DMASTConstantPath","fields":{"Value":{
                "kind":"DMASTPath","fields":{"Path":"/datum/test"}}}}
        }}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
            "name":"New","file":"code/test.dm","line":2,"parameters":[],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[assignment]}}});
        let source = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unproven-initialization"));
    }

    #[test]
    fn one_storage_type_and_explicit_null() {
        let symbols = Symbols::default();
        assert_eq!(
            Ty::Path("/obj/item".into()).join(&Ty::Path("/obj/item/tool".into()), &symbols),
            Ty::Path("/obj/item".into())
        );
        assert!(!Ty::Path("/obj/item".into()).accepts(&Ty::Null, &symbols));
        assert!(Ty::parse("/obj/item?").accepts(&Ty::Null, &symbols));
        assert!(!Ty::Num.accepts(&Ty::Unknown, &symbols));
        assert_eq!(Ty::Num.join(&Ty::Text, &symbols), Ty::Unknown);
        assert!(Ty::parse("list<unknown>").accepts(&Ty::parse("assoc<text,num>"), &symbols));
        assert!(!Ty::parse("list<num>").accepts(&Ty::parse("assoc<text,num>"), &symbols));
        assert_eq!(
            Ty::TypePath("/client/proc/a".into())
                .join(&Ty::TypePath("/client/proc/b".into()), &symbols),
            Ty::TypePath("/client/proc".into())
        );
    }

    #[test]
    fn unknown_collection_elements_remain_unresolved_at_assignment() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let node = serde_json::json!({"kind":"DMASTAssign",
            "file":"code/test.dm","line":1});
        checker.assignment_with_policy(
            &node,
            &Ty::parse("list<num>"),
            &Ty::parse("list<unknown>"),
            "items",
            true,
        );
        assert_eq!(checker.findings.last().unwrap().rule, "unknown-type-flow");
        assert!(checker
            .findings
            .last()
            .unwrap()
            .message
            .contains("source type needs proof"));
        checker.assignment_with_policy(
            &node,
            &Ty::parse("list<unknown>"),
            &Ty::parse("list<num>"),
            "items",
            true,
        );
        assert!(checker
            .findings
            .last()
            .unwrap()
            .message
            .contains("destination type needs a contract"));
        checker.assignment_with_policy(
            &node,
            &Ty::parse("list<unknown>"),
            &Ty::parse("list<unknown>"),
            "items",
            true,
        );
        assert_eq!(checker.coverage.unresolved_source_types, 1);
        assert_eq!(checker.coverage.unresolved_destination_types, 1);
        assert_eq!(checker.coverage.unresolved_both_types, 1);
        checker.assignment_with_policy(
            &node,
            &Ty::parse("list<num>"),
            &Ty::parse("list<text>"),
            "items",
            true,
        );
        assert_eq!(
            checker.findings.last().unwrap().rule,
            "strict-type-assignment"
        );
        let prior = checker.findings.len();
        checker.assignment_with_policy(&node, &Ty::parse("list<num>?"), &Ty::Null, "items", true);
        assert_eq!(checker.findings.len(), prior);
        let proc_key = ("/datum/test".into(), "Accept".into());
        checker.add_param_evidence(&proc_key, 0, Ty::parse("list<unknown>"));
        assert_eq!(
            checker.param_evidence[&(proc_key.0, proc_key.1, 0)].unresolved,
            1
        );
    }

    #[test]
    fn empty_list_uses_a_declared_collection_type_without_inventing_elements() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let empty = serde_json::json!({"kind":"DMASTList","fields":{"Values":[]}});
        assert_eq!(
            checker.expression(&empty, &HashMap::new(), "/datum/test"),
            Ty::EmptyList
        );
        assert_eq!(
            checker.unresolved_cause(&empty, "/datum/test", &Env::default()),
            "Empty collection literal"
        );
        let node = serde_json::json!({"kind":"DMASTAssign",
            "file":"code/test.dm","line":1});
        let expected = Ty::parse("list<num>");
        checker.assignment_with_policy(&node, &expected, &Ty::EmptyList, "items", true);
        assert!(checker.findings.is_empty());
        assert_eq!(contextual_empty_list(Ty::EmptyList, &expected), expected);
        checker.assignment_with_policy(&node, &Ty::EmptyList, &Ty::EmptyList, "items", true);
        assert_eq!(checker.findings.last().unwrap().rule, "unknown-type-flow");
        checker.assignment_with_policy(&node, &Ty::Num, &Ty::EmptyList, "items", true);
        assert_eq!(
            checker.findings.last().unwrap().rule,
            "strict-type-assignment"
        );

        let mut env = Env::default();
        env.slots.insert("items".into(), Ty::EmptyList);
        env.facts.insert("items".into(), Ty::EmptyList);
        env.assigned.insert("items".into());
        let write = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":2,"fields":{"Expression":{
            "kind":"DMASTAssign","file":"code/test.dm","line":2,"fields":{
                "LHS":{"kind":"DMASTDereference","file":"code/test.dm",
                    "line":2,"fields":{
                    "Expression":{"kind":"DMASTIdentifier","fields":{
                        "Identifier":"items"}},
                    "Operations":[{"kind":"IndexOperation","fields":{
                        "Index":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                        "Safe":false}}]}},
                "RHS":{"kind":"DMASTConstantString","fields":{"Value":"wrong"}}
            }}}});
        let sig = Signature {
            parameters: vec![],
            result: Ty::Void,
            result_required: false,
            inferred_nullable_result: false,
            path: "code/test.dm".into(),
            line: 1,
        };
        checker.statement(&write, "/datum/test", &sig, &mut env);
        assert_eq!(env.facts["items"], Ty::Unknown);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-index-write"));
        checker.fields.insert(
            ("/datum/test".into(), "items".into()),
            FieldInfo {
                ty: Ty::parse("list<num>"),
                explicit_type: true,
                evidence: Ty::EmptyList,
                origin: node.clone(),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let field_write = serde_json::json!({"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "RHS":empty
        }});
        checker.register_writes(
            &field_write,
            "/datum/test",
            &HashMap::new(),
            &HashSet::new(),
        );
        assert!(!checker.fields[&("/datum/test".into(), "items".into())].saw_unknown_write);
    }

    #[test]
    fn alist_literals_keep_their_distinct_numeric_key_semantics() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let literal = serde_json::json!({"kind":"DMASTList","fields":{
        "IsAList":true,"Values":[{"kind":"DMASTCallParameter","fields":{
            "Key":{"kind":"DMASTConstantInteger","fields":{"Value":45}},
            "Value":{"kind":"DMASTConstantInteger","fields":{"Value":50}}
        }}]}});
        let expected = Ty::parse("alist<num,num>");
        assert_eq!(
            checker.expression(&literal, &HashMap::new(), "/datum/test"),
            expected
        );
        assert_eq!(Ty::parse("/alist"), Ty::parse("alist<unknown,unknown>"));
        assert!(!Ty::parse("list<num>").accepts(&expected, &symbols));
        assert!(!expected.accepts(&Ty::EmptyList, &symbols));
        assert!(expected.accepts(&Ty::EmptyAlist, &symbols));
        let empty = serde_json::json!({"kind":"DMASTList","fields":{
            "IsAList":true,"Values":[]}});
        assert_eq!(
            checker.expression(&empty, &HashMap::new(), "/datum/test"),
            Ty::EmptyAlist
        );
        let read = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "Operations":[{"kind":"IndexOperation","fields":{
                "Index":{"kind":"DMASTConstantInteger","fields":{"Value":45}},
                "Safe":false}}]}});
        let vars = HashMap::from([("items".into(), expected)]);
        assert_eq!(
            checker.expression(&read, &vars, "/datum/test"),
            Ty::parse("num?")
        );
        let mut new_list = serde_json::json!({"kind":"DMASTNewPath","fields":{
            "Path":{"kind":"DMASTConstantPath","fields":{"Value":{
                "kind":"DMASTPath","fields":{"Path":"/list"}}}},
            "Parameters":[]}});
        assert_eq!(
            checker.expression(&new_list, &HashMap::new(), "/datum/test"),
            Ty::EmptyList
        );
        new_list["fields"]["Parameters"] = serde_json::json!([
            {"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":2}}}}
        ]);
        assert_eq!(
            checker.expression(&new_list, &HashMap::new(), "/datum/test"),
            Ty::parse("list<unknown>")
        );
        let base = Signature {
            parameters: vec![ParamInfo {
                name: "data".into(),
                ty: Ty::parse("/alist"),
                has_default: false,
                default_ty: Ty::Unknown,
                inferred_from_calls: false,
            }],
            result: Ty::parse("/alist"),
            result_required: true,
            inferred_nullable_result: false,
            path: "code/test.dm".into(),
            line: 1,
        };
        let child = Signature {
            parameters: vec![ParamInfo {
                name: "data".into(),
                ty: Ty::parse("alist<num,num>"),
                has_default: false,
                default_ty: Ty::Unknown,
                inferred_from_calls: false,
            }],
            result: Ty::parse("alist<num,num>"),
            result_required: true,
            inferred_nullable_result: false,
            path: "code/test.dm".into(),
            line: 2,
        };
        checker
            .procs
            .insert(("/datum/test".into(), "Run".into()), base);
        checker
            .procs
            .insert(("/datum/test/child".into(), "Run".into()), child);
        checker.check_overrides();
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unknown-override-type"));
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unknown-override-result"));
    }

    #[test]
    fn unary_numeric_operators_require_a_proved_number() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let mut env = Env::default();
        env.slots.insert("value".into(), Ty::Num);
        env.assigned.insert("value".into());
        let operation = serde_json::json!({"kind":"DMASTPostIncrement",
            "file":"code/test.dm","line":2,"fields":{
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}}}});
        env.facts.insert("value".into(), Ty::Num);
        assert_eq!(
            checker.expression(&operation, &env.facts, "/datum/test"),
            Ty::Num
        );
        checker.inspect_expr(&operation, "/datum/test", &env);
        assert!(!checker
            .findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                || finding.rule == "unknown-type-flow"));
        env.facts.insert("value".into(), Ty::Text);
        assert_eq!(
            checker.expression(&operation, &env.facts, "/datum/test"),
            Ty::Unknown
        );
        checker.inspect_expr(&operation, "/datum/test", &env);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("numeric operator operand")));
        env.facts.insert("value".into(), Ty::Unknown);
        checker.inspect_expr(&operation, "/datum/test", &env);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unknown-type-flow"
                && finding.message.contains("numeric operator operand")));
        let membership = serde_json::json!({"kind":"DMASTExpressionIn","fields":{
            "LHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "RHS":{"kind":"DMASTConstantNull"}}});
        assert_eq!(
            checker.expression(&membership, &env.facts, "/datum/test"),
            Ty::Num
        );
    }

    #[test]
    fn type_enumeration_keeps_proved_typepath_elements() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let mut call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"subtypesof"}},
            "Parameters":[{"fields":{"Value":{"kind":"DMASTConstantPath","fields":{
                "Value":{"fields":{"Path":"/datum/affliction"}}}},"Key":null}}]
        }});
        assert_eq!(
            checker.expression(&call, &HashMap::new(), "/datum/test"),
            Ty::List(Box::new(Ty::TypePath("/datum/affliction".into())))
        );
        checker.inspect_expr(&call, "/datum/test", &Env::default());
        assert_eq!(checker.coverage.resolved_calls, 1);
        assert!(!checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-direct-call"));
        call["fields"]["Parameters"][0]["fields"]["Value"] =
            serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"unknown"}});
        assert_eq!(
            checker.expression(&call, &HashMap::new(), "/datum/test"),
            Ty::Unknown
        );
        checker.inspect_expr(&call, "/datum/test", &Env::default());
        assert_eq!(checker.coverage.unresolved_calls, 1);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-type-enumeration"));
        let islist = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"islist"}},
            "Parameters":[{"fields":{"Value":{"kind":"DMASTIdentifier",
                "fields":{"Identifier":"unknown"}},"Key":null}}]
        }});
        assert_eq!(
            checker.expression(&islist, &HashMap::new(), "/datum/test"),
            Ty::Num
        );
        assert!(!contains_unknown_effect(&islist));
        checker.inspect_expr(&islist, "/datum/test", &Env::default());
        assert_eq!(checker.coverage.resolved_calls, 2);

        let add = serde_json::json!({"kind":"DMASTAdd","fields":{
            "LHS":{"kind":"DMASTList","fields":{"Values":[]}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
        }});
        assert_eq!(
            checker.expression(&add, &HashMap::new(), "/datum/test"),
            Ty::List(Box::new(Ty::Num))
        );
        let text_add = serde_json::json!({"kind":"DMASTAdd","fields":{
            "LHS":{"kind":"DMASTConstantString","fields":{"Value":"a"}},
            "RHS":{"kind":"DMASTConstantString","fields":{"Value":"b"}}
        }});
        assert_eq!(
            checker.expression(&text_add, &HashMap::new(), "/datum/test"),
            Ty::Text
        );
        let nested = serde_json::json!({"kind":"DMASTAdd","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"nested"}},
            "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"inner"}}
        }});
        let vars = HashMap::from([
            ("nested".into(), Ty::parse("list<list<num>>")),
            ("inner".into(), Ty::parse("list<num>")),
        ]);
        assert_eq!(
            checker.expression(&nested, &vars, "/datum/test"),
            Ty::List(Box::new(Ty::Unknown))
        );
        let append = serde_json::json!({"kind":"DMASTAppend","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"count"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
        }});
        let count = HashMap::from([("count".into(), Ty::Num)]);
        assert_eq!(checker.expression(&append, &count, "/datum/test"), Ty::Num);
        assert!(contains_unknown_effect(&append));
        let mut append_statement = serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":5,"fields":{"Expression":append}});
        append_statement["fields"]["Expression"]["file"] = Value::String("code/test.dm".into());
        let signature = Signature {
            parameters: Vec::new(),
            result: Ty::Void,
            result_required: false,
            inferred_nullable_result: false,
            path: "code/test.dm".into(),
            line: 1,
        };
        let mut env = Env::default();
        checker.statement(&append_statement, "/datum/test", &signature, &mut env);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-append-target"));
        checker.findings.clear();
        env.slots.insert("count".into(), Ty::Num);
        env.facts.insert("count".into(), Ty::Num);
        env.facts
            .insert("other".into(), Ty::Path("/datum/test".into()));
        checker.statement(&append_statement, "/datum/test", &signature, &mut env);
        assert!(!checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-append-target"));
        assert_eq!(
            env.facts.get("other"),
            Some(&Ty::Path("/datum/test".into()))
        );
        let mut list_statement = append_statement.clone();
        list_statement["fields"]["Expression"]["fields"]["LHS"]["fields"]["Identifier"] =
            Value::String("items".into());
        let mut list_env = Env::default();
        list_env
            .slots
            .insert("items".into(), Ty::parse("list<num>"));
        list_env
            .facts
            .insert("items".into(), Ty::parse("list<num>"));
        list_env
            .slots
            .insert("alias".into(), Ty::parse("list<num>"));
        list_env
            .facts
            .insert("alias".into(), Ty::parse("list<num>"));
        checker.statement(&list_statement, "/datum/test", &signature, &mut list_env);
        assert_eq!(list_env.facts.get("items"), Some(&Ty::parse("list<num>")));
        assert_eq!(list_env.facts.get("alias"), Some(&Ty::Unknown));
    }

    #[test]
    fn static_local_starts_nullable_and_retains_prior_invocations() {
        let declaration = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
        "file":"code/test.dm","line":2,"fields":{
            "Name":"cache","Type":{"fields":{"Path":"/list"}},
            "ValueType":"\"anything\"","Value":null,"IsGlobal":true
        }});
        let cache = serde_json::json!({"kind":"DMASTIdentifier","file":"code/test.dm",
            "line":3,"fields":{"Identifier":"cache"}});
        let read = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":3,"fields":{"Expression":{
            "kind":"DMASTDereference","file":"code/test.dm","line":3,
            "fields":{"Expression":cache,"Operations":[{
                "kind":"FieldOperation","fields":{"Identifier":"len","Safe":false}
            }]}
        }}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Read",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[declaration,read]}
        }});
        let source = proc.to_string();
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "read-before-assignment"));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
        assert!(coverage.unresolved_declarations > 0);
        let contracts = crate::contracts::collect(
            "// dm-health: local cache list<text>\n/datum/test/proc/Read()\n",
        );
        let (typed_findings, typed_coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!typed_findings
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
        assert!(typed_findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));
        assert!(typed_coverage.known_declarations > coverage.known_declarations);
        let misspelled = crate::contracts::collect(
            "// dm-health: local missing list<text>\n/datum/test/proc/Read()\n",
        );
        let (missing_findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &misspelled,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(missing_findings
            .iter()
            .any(|finding| finding.rule == "missing-local-type-target"));
    }

    #[test]
    fn untyped_local_storage_uses_every_write_without_proving_initialization() {
        let declaration = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":2,"fields":{
                "Name":"value","Type":null,"ValueType":"\"anything\"",
                "Value":null,"IsGlobal":false}});
        let write = |line: usize, rhs: Value| {
            serde_json::json!({
            "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":line,
            "fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm",
                "line":line,"fields":{"LHS":{"kind":"DMASTIdentifier","fields":{
                    "Identifier":"value"}},"RHS":rhs}}}})
        };
        let number = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}});
        let text = serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"bad"}});
        let null = serde_json::json!({"kind":"DMASTConstantNull"});
        let check_statements = |statements: Vec<Value>| {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
                "name":"Run","file":"code/test.dm","line":1,"parameters":[],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":statements}}});
            let source = proc.to_string();
            analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
            .0
        };
        let check = |writes: Vec<Value>| {
            let mut statements = vec![declaration.clone()];
            statements.extend(writes);
            check_statements(statements)
        };
        let proved = check(vec![write(3, number.clone()), write(4, number)]);
        assert!(!proved
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
        let conflict = check(vec![
            write(
                3,
                serde_json::json!({"kind":"DMASTConstantInteger",
            "fields":{"Value":1}}),
            ),
            write(4, text),
        ]);
        assert!(conflict
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
        let nullable = check(vec![
            write(
                3,
                serde_json::json!({"kind":"DMASTConstantInteger",
            "fields":{"Value":1}}),
            ),
            write(4, null),
        ]);
        assert!(nullable
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
        let shadowed = check(vec![
            write(
                3,
                serde_json::json!({
            "kind":"DMASTConstantInteger","fields":{"Value":1}}),
            ),
            declaration.clone(),
        ]);
        assert!(shadowed
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
        let before = check_statements(vec![
            write(
                1,
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
            ),
            declaration,
        ]);
        assert!(before
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"));
    }

    #[test]
    fn local_storage_follows_only_definitely_initialized_sources() {
        let declaration = |name: &str, line: usize| {
            serde_json::json!({
            "kind":"DMASTProcStatementVarDeclaration","file":"code/test.dm","line":line,
            "fields":{"Name":name,"Type":null,"ValueType":"\"anything\"",
                "Value":null,"IsGlobal":false}})
        };
        let write = |name: &str, line: usize, rhs: Value| {
            serde_json::json!({
            "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":line,
            "fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm",
                "line":line,"fields":{"LHS":{"kind":"DMASTIdentifier","fields":{
                    "Identifier":name}},"RHS":rhs}}}})
        };
        let ident = |name: &str| {
            serde_json::json!({
            "kind":"DMASTIdentifier","fields":{"Identifier":name}})
        };
        let number = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}});
        let check = |statements: Vec<Value>| {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
                "name":"Run","file":"code/test.dm","line":1,"parameters":[],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":statements}}});
            let source = proc.to_string();
            analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap()
            .0
        };
        let proved = check(vec![
            declaration("source", 2),
            declaration("target", 3),
            write("source", 4, number.clone()),
            write("target", 5, ident("source")),
        ]);
        assert!(!proved
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"
                && finding.message.contains("target")));
        let unproved = check(vec![
            declaration("source", 2),
            declaration("target", 3),
            write("target", 4, ident("source")),
            write("source", 5, number),
        ]);
        assert!(unproved
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"
                && finding.message.contains("target")));
        let branch = |else_writes: bool| {
            serde_json::json!({
            "kind":"DMASTProcStatementIf","file":"code/test.dm","line":4,
            "fields":{"Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                    write("source", 5, serde_json::json!({"kind":"DMASTConstantInteger",
                        "fields":{"Value":1}}))]}},
                "ElseBody":{"kind":"DMASTProcBlockInner","fields":{"Statements":
                    if else_writes { vec![write("source", 6,
                        serde_json::json!({"kind":"DMASTConstantInteger",
                            "fields":{"Value":2}}))] } else { vec![] }}}}})
        };
        let both = check(vec![
            declaration("source", 2),
            declaration("target", 3),
            branch(true),
            write("target", 7, ident("source")),
        ]);
        assert!(!both
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"
                && finding.message.contains("target")));
        let one = check(vec![
            declaration("source", 2),
            declaration("target", 3),
            branch(false),
            write("target", 7, ident("source")),
        ]);
        assert!(one
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"
                && finding.message.contains("target")));
        let loop_node = serde_json::json!({"kind":"DMASTProcStatementWhile",
            "file":"code/test.dm","line":5,"fields":{
                "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                    write("source", 6, serde_json::json!({"kind":"DMASTConstantNull"}))]}}}});
        let loop_changed = check(vec![
            declaration("source", 2),
            declaration("target", 3),
            write(
                "source",
                4,
                serde_json::json!({"kind":"DMASTConstantInteger",
                "fields":{"Value":1}}),
            ),
            loop_node,
            write("target", 7, ident("source")),
        ]);
        assert!(loop_changed
            .iter()
            .any(|finding| finding.rule == "unknown-local-type"
                && finding.message.contains("target")));
    }

    #[test]
    fn isnull_guard_narrows_true_branch_to_null() {
        let guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"isnull"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                "Key":null}}]}});
        let mut true_branch = HashMap::from([("item".into(), Ty::parse("/obj/item?"))]);
        narrow(&guard, true, &mut true_branch);
        assert_eq!(true_branch["item"], Ty::Null);
        let mut false_branch = HashMap::from([("item".into(), Ty::parse("/obj/item?"))]);
        narrow(&guard, false, &mut false_branch);
        assert_eq!(false_branch["item"], Ty::Path("/obj/item".into()));
    }

    #[test]
    fn literal_index_guard_tracks_the_specific_collection_entry() {
        let entry = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"belly_data"}},
            "Operations":[{"kind":"IndexOperation","fields":{
                "Index":{"kind":"DMASTConstantString","fields":{"Value":"name"}},
                "Safe":false}}]}});
        let key = place(&entry).unwrap();
        assert_eq!(key, "belly_data.[\"name\"]");
        let guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"istext"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{
                "Value":entry,"Key":null}}]}});
        let mut vars = HashMap::from([(key.clone(), Ty::Unknown)]);
        narrow(&guard, true, &mut vars);
        assert_eq!(vars[&key], Ty::Text);
        overwrite_place_fact(&mut vars, "belly_data", Ty::List(Box::new(Ty::Unknown)));
        assert!(!vars.contains_key(&key));
    }

    #[test]
    fn local_literal_record_tracks_keys_and_loses_shape_on_dynamic_write() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let sig = Signature {
            parameters: vec![],
            result: Ty::Unknown,
            result_required: false,
            inferred_nullable_result: false,
            path: "code/test.dm".into(),
            line: 1,
        };
        let mut env = Env::default();
        let declaration = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":2,"fields":{
                "Name":"tab_data","Type":"/list","ValueType":null,"IsGlobal":false,
                "Value":{"kind":"DMASTList","fields":{"Values":[
                    {"kind":"DMASTCallParameter","fields":{
                        "Key":{"kind":"DMASTConstantString","fields":{"Value":"name"}},
                        "Value":{"kind":"DMASTConstantString","fields":{"Value":"first"}}}}
                ],"IsAList":false}}}});
        checker.statement(&declaration, "/datum/test", &sig, &mut env);
        assert!(matches!(env.facts.get("tab_data"), Some(Ty::Record(_))));
        let write = |index: Value| {
            serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":3,"fields":{"Expression":{
                "kind":"DMASTAssign","file":"code/test.dm","line":3,"fields":{
                    "LHS":{"kind":"DMASTDereference","fields":{
                        "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"tab_data"}},
                        "Operations":[{"kind":"IndexOperation","fields":{
                            "Index":index,"Safe":false}}]}},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":7}}}}}})
        };
        checker.statement(
            &write(serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"count"}})),
            "/datum/test",
            &sig,
            &mut env,
        );
        assert!(matches!(env.facts.get("tab_data"), Some(Ty::Record(fields))
            if fields.get("name") == Some(&(Ty::Text, false))
                && fields.get("count") == Some(&(Ty::Num, false))));
        let scalar_read = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"tab_data"}},
            "Operations":[{"kind":"IndexOperation","fields":{
                "Index":{"kind":"DMASTConstantString","fields":{"Value":"count"}},
                "Safe":false}}]}});
        assert!(env.record_references(&scalar_read).is_empty());
        let mut aliased = env.clone();
        let alias = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":4,"fields":{
                "Name":"other","Type":"/list","ValueType":null,"IsGlobal":false,
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"tab_data"}}}});
        checker.statement(&alias, "/datum/test", &sig, &mut aliased);
        assert_eq!(aliased.facts.get("tab_data"), Some(&Ty::Unknown));
        assert_eq!(aliased.facts.get("other"), Some(&Ty::Unknown));
        let mut affected = env.clone();
        affected.invalidate_after(&serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{
                "Identifier":"Unknown"}},"Parameters":[]}}));
        assert_eq!(affected.facts.get("tab_data"), Some(&Ty::Unknown));
        let joined = env.facts["tab_data"].join(&Ty::EmptyList, &symbols);
        assert!(matches!(joined, Ty::Record(fields)
            if fields.values().all(|(_, optional)| *optional)));
        checker.statement(
            &write(serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"key"}})),
            "/datum/test",
            &sig,
            &mut env,
        );
        assert_eq!(env.facts.get("tab_data"), Some(&Ty::Unknown));

        let mut fresh = Env::default();
        let fresh_declaration = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":7,"fields":{
                "Name":"items","Type":"/list","ValueType":null,"IsGlobal":false,
                "Value":{"kind":"DMASTList","fields":{"Values":[],"IsAList":false}}}});
        checker.statement(&fresh_declaration, "/datum/test", &sig, &mut fresh);
        assert_eq!(fresh.facts.get("items"), Some(&Ty::EmptyList));
        assert!(fresh.fresh_collections.contains("items"));
        let indexed = |value: Value| {
            serde_json::json!({"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":8,"fields":{"Expression":{
                "kind":"DMASTAssign","file":"code/test.dm","line":8,"fields":{
                    "LHS":{"kind":"DMASTDereference","fields":{
                        "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
                        "Operations":[{"kind":"IndexOperation","fields":{
                            "Index":{"kind":"DMASTConstantString","fields":{"Value":"key"}},
                            "Safe":false}}]}},"RHS":value}}}})
        };
        checker.statement(
            &indexed(serde_json::json!({"kind":"DMASTConstantInteger",
            "fields":{"Value":5}})),
            "/datum/test",
            &sig,
            &mut fresh,
        );
        assert_eq!(
            fresh.facts.get("items"),
            Some(&Ty::Record(BTreeMap::from([(
                "key".into(),
                (Ty::Num, false)
            )])))
        );
        let unrelated_call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Unknown"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}]}});
        fresh.invalidate_after(&unrelated_call);
        assert_eq!(
            fresh.facts.get("items"),
            Some(&Ty::Record(BTreeMap::from([(
                "key".into(),
                (Ty::Num, false)
            )])))
        );
        let mut escaped = fresh.clone();
        let escaping_call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Unknown"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}}}}]}});
        escaped.invalidate_after(&escaping_call);
        assert_eq!(escaped.facts.get("items"), Some(&Ty::Unknown));
        let mut aliased_fresh = fresh.clone();
        aliased_fresh.escape_fresh_references(&serde_json::json!({"kind":"DMASTIdentifier",
            "fields":{"Identifier":"items"}}));
        assert_eq!(aliased_fresh.facts.get("items"), Some(&Ty::Unknown));
        checker.statement(
            &indexed(serde_json::json!({"kind":"DMASTIdentifier",
            "fields":{"Identifier":"unproved"}})),
            "/datum/test",
            &sig,
            &mut fresh,
        );
        assert_eq!(
            fresh.facts.get("items"),
            Some(&Ty::Record(BTreeMap::from([(
                "key".into(),
                (Ty::Unknown, false)
            ),])))
        );
    }

    #[test]
    fn native_atom_kind_guards_narrow_unknown_receivers() {
        for (builtin, expected) in [
            ("isarea", "/area"),
            ("ismob", "/mob"),
            ("isobj", "/obj"),
            ("isturf", "/turf"),
            ("ismovable", "/atom/movable"),
        ] {
            let guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
                "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{
                    "Identifier":builtin}},
                "Parameters":[{"kind":"DMASTCallParameter","fields":{
                    "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"target"}},
                    "Key":null}}]}});
            let mut facts = HashMap::from([("target".into(), Ty::Unknown)]);
            assert!(!contains_unknown_effect(&guard));
            narrow(&guard, true, &mut facts);
            assert_eq!(facts["target"], Ty::Path(expected.into()));
            facts.insert("target".into(), Ty::Unknown);
            narrow(&guard, false, &mut facts);
            assert_eq!(facts["target"], Ty::Unknown);
        }
        let guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{
                "Identifier":"ismob"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"target"}},
                "Key":null}}]}});
        let mut facts = HashMap::from([("target".into(), Ty::parse("/mob/living?"))]);
        narrow(&guard, true, &mut facts);
        assert_eq!(facts["target"], Ty::Path("/mob/living".into()));
    }

    #[test]
    fn guard_narrows_optional_local() {
        let mut vars = HashMap::from([("item".into(), Ty::parse("/obj/item?"))]);
        let guard = serde_json::json!({"kind":"DMASTNotEqual","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
            "RHS":{"kind":"DMASTConstantNull"}
        }});
        narrow(&guard, true, &mut vars);
        assert_eq!(vars["item"], Ty::Path("/obj/item".into()));
        vars.insert("untyped".into(), Ty::Unknown);
        let unknown_guard = serde_json::json!({"kind":"DMASTIsNull","fields":{
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"untyped"}}}});
        narrow(&unknown_guard, false, &mut vars);
        assert_eq!(vars["untyped"], Ty::NonNullUnknown);
        assert!(!vars["untyped"].may_be_null());
        assert!(!vars["untyped"].is_precise());
        let actual_ast = serde_json::json!({"kind":"DMASTIsNull","fields":{
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}}}});
        vars.insert("item".into(), Ty::parse("/obj/item?"));
        narrow(&actual_ast, false, &mut vars);
        assert_eq!(vars["item"], Ty::Path("/obj/item".into()));
        let subtype_guard = serde_json::json!({"kind":"DMASTIsType","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
            "RHS":{"kind":"DMASTConstantPath","fields":{"Value":{
                "kind":"DMASTPath","fields":{"Path":"/obj/item/tool"}}}}}});
        narrow(&subtype_guard, true, &mut vars);
        assert_eq!(vars["item"], Ty::Path("/obj/item/tool".into()));

        let list_guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"islist"}},
            "Parameters":[{"fields":{"Value":{"kind":"DMASTIdentifier",
                "fields":{"Identifier":"items"}},"Key":null}}]
        }});
        vars.insert("items".into(), Ty::Unknown);
        narrow(&list_guard, true, &mut vars);
        assert_eq!(vars["items"], Ty::List(Box::new(Ty::Unknown)));
        for (builtin, expected) in [("isnum", Ty::Num), ("istext", Ty::Text)] {
            let guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
                "Callable":{"kind":"DMASTCallableProcIdentifier",
                    "fields":{"Identifier":builtin}},
                "Parameters":[{"kind":"DMASTCallParameter","fields":{
                    "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}},
                    "Key":null}}]}});
            vars.insert("value".into(), Ty::Unknown);
            assert!(!contains_unknown_effect(&guard));
            narrow(&guard, true, &mut vars);
            assert_eq!(vars["value"], expected);
            vars.insert("value".into(), Ty::Unknown);
            narrow(&guard, false, &mut vars);
            assert_eq!(vars["value"], Ty::Unknown);
        }
        let native_list_guard = serde_json::json!({"kind":"DMASTIsType","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"other"}},
            "RHS":{"kind":"DMASTConstantPath","fields":{"Value":{
                "kind":"DMASTPath","fields":{"Path":"/list"}}}}
        }});
        vars.insert("other".into(), Ty::Unknown);
        narrow(&native_list_guard, true, &mut vars);
        assert_eq!(vars["other"], Ty::List(Box::new(Ty::Unknown)));

        let mut env = Env::default();
        env.slots.insert(
            "external".into(),
            Ty::Path("/obj/item/organ/external".into()),
        );
        env.facts
            .insert("external".into(), Ty::Path("/obj/item/organ".into()));
        let implicit = serde_json::json!({"kind":"DMASTImplicitIsType","fields":{
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"external"}}
        }});
        narrow_env(&implicit, true, &mut env);
        assert_eq!(
            env.facts["external"],
            Ty::Path("/obj/item/organ/external".into())
        );
    }

    #[test]
    fn ispath_bound_proves_only_constructible_dynamic_paths() {
        let symbols = Symbols::default();
        assert!(!symbols.is_subtype("/proc", "/datum"));
        assert!(!symbols.is_subtype("/datum/test/proc/Run", "/datum"));
        let selection = Selection::default();
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let mut guard = serde_json::json!({"kind":"DMASTProcCall","fields":{
        "Callable":{"kind":"DMASTCallableProcIdentifier",
            "fields":{"Identifier":"ispath"}},
        "Parameters":[
            {"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"path"}}}},
            {"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/datum"}}}}}}
        ]}});
        let dynamic_new = serde_json::json!({"kind":"DMASTNewExpr","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"path"}},
            "Parameters":[]}});
        let text_to_path = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{
                "Identifier":"text2path"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantString","fields":{"Value":"/datum/test"}}}}]
        }});
        let parsed = checker.expression(&text_to_path, &HashMap::new(), "/datum/test");
        assert_eq!(parsed, Ty::Nullable(Box::new(Ty::TypePath("/".into()))));
        let mut nontext_input = text_to_path.clone();
        nontext_input["fields"]["Parameters"][0]["fields"]["Value"] =
            serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":7}});
        assert_eq!(
            checker.expression(&nontext_input, &HashMap::new(), "/datum/test"),
            Ty::Unknown
        );
        let mut vars = HashMap::from([("path".into(), parsed)]);
        assert_eq!(
            checker.expression(&dynamic_new, &vars, "/datum/test"),
            Ty::Unknown
        );
        assert!(checked_ispath_builtin(&guard));
        narrow(&guard, true, &mut vars);
        assert_eq!(vars["path"], Ty::TypePath("/datum".into()));
        assert_eq!(
            checker.expression(&dynamic_new, &vars, "/datum/test"),
            Ty::Path("/datum".into())
        );
        guard["fields"]["Parameters"][1]["fields"]["Value"]["fields"]["Value"]["fields"]["Path"] =
            Value::String("/proc".into());
        vars.insert("path".into(), Ty::Unknown);
        narrow(&guard, true, &mut vars);
        assert_eq!(
            checker.expression(&dynamic_new, &vars, "/datum/test"),
            Ty::Unknown
        );
        guard["fields"]["Parameters"][1]["fields"]["Value"] =
            serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"other"}});
        vars.insert("path".into(), Ty::Unknown);
        assert!(!checked_ispath_builtin(&guard));
        narrow(&guard, true, &mut vars);
        assert_eq!(vars["path"], Ty::Unknown);
    }

    #[test]
    fn literal_vars_index_uses_declared_field_type_for_reads_and_writes() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test",
            "name":"count","file":"code/test.dm","line":1,"type":"num",
            "valueType":"num","initializer":{"kind":"DMASTConstantInteger",
                "fields":{"Value":1}}});
        let reflected = serde_json::json!({"kind":"DMASTDereference",
        "file":"code/test.dm","line":3,"fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"vars"}},
            "Operations":[{"kind":"IndexOperation","fields":{
                "Index":{"kind":"DMASTConstantString","fields":{"Value":"count"}},
                "Safe":false}}]
        }});
        let write = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":3,"fields":{
            "Expression":{"kind":"DMASTAssign","file":"code/test.dm",
                "line":3,"fields":{"LHS":reflected.clone(),"RHS":{
                    "kind":"DMASTConstantString","fields":{"Value":"bad"}}}}
        }});
        let read = serde_json::json!({"kind":"DMASTProcStatementReturn",
            "file":"code/test.dm","line":4,"fields":{"Value":reflected}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
            "name":"Read","file":"code/test.dm","line":2,"parameters":[],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[write,read]}}});
        let source = format!("{}\n{}\n", field, proc);
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("reflected")));
        assert!(!findings.iter().any(|finding| matches!(
            finding.rule,
            "unresolved-index" | "unresolved-index-write" | "unknown-return-type"
        )));
    }

    #[test]
    fn safe_reflected_field_read_remains_nullable() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test",
            "name":"count","file":"code/test.dm","line":1,"type":"num",
            "valueType":"num","initializer":{"kind":"DMASTConstantInteger",
                "fields":{"Value":1}}});
        let mut reflected = serde_json::json!({"kind":"DMASTDereference",
        "file":"code/test.dm","line":3,"fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"vars"}},
            "Operations":[{"kind":"IndexOperation","fields":{
                "Index":{"kind":"DMASTConstantString","fields":{"Value":"count"}},
                "Safe":true}}]
        }});
        let contracts =
            crate::contracts::collect("// dm-health: returns num\n/datum/test/proc/Read()\n");
        for (safe, expect_error) in [(true, true), (false, false)] {
            reflected["fields"]["Operations"][0]["fields"]["Safe"] = Value::Bool(safe);
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
            "name":"Read","file":"code/test.dm","line":2,"parameters":[],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementReturn","file":"code/test.dm",
                 "line":3,"fields":{"Value":reflected.clone()}}
            ]}}});
            let source = format!("{}\n{}\n", field, proc);
            let (findings, _) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "strict-type-assignment"),
                expect_error,
                "safe={safe}, findings={findings:?}"
            );
        }
    }

    #[test]
    fn ternary_checks_each_result_under_its_guard() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let expression = serde_json::json!({"kind":"DMASTTernary","fields":{
            "A":{"kind":"DMASTNotEqual","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
                "RHS":{"kind":"DMASTConstantNull"}}},
            "B":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},
            "C":{"kind":"DMASTNewPath","fields":{"Path":{
                "kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/obj/item"}}}}}}
        }});
        let vars = HashMap::from([("item".into(), Ty::parse("/obj/item?"))]);
        assert_eq!(
            checker.expression(&expression, &vars, "/datum/test"),
            Ty::Path("/obj/item".into())
        );
        let unknown =
            serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"missing"}});
        let text = serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"fallback"}});
        let zero = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":0}});
        let one = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}});
        for (condition, expected) in [(&zero, Ty::Text), (&one, Ty::Unknown)] {
            let ternary = serde_json::json!({"kind":"DMASTTernary","fields":{
                "A":condition,"B":unknown,"C":text}});
            assert_eq!(checker.expression(&ternary, &vars, "/datum/test"), expected);
        }
        for (operator, lhs, expected) in [
            ("DMASTOr", &zero, Ty::Text),
            ("DMASTAnd", &zero, Ty::Num),
            ("DMASTOr", &one, Ty::Num),
            ("DMASTAnd", &one, Ty::Text),
        ] {
            let logical = serde_json::json!({"kind":operator,"fields":{"LHS":lhs,"RHS":text}});
            assert_eq!(checker.expression(&logical, &vars, "/datum/test"), expected);
        }
    }

    #[test]
    fn unknown_receiver_can_be_nonnull_without_a_proved_member_type() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let mut env = Env::default();
        env.slots.insert("value".into(), Ty::Unknown);
        env.facts.insert("value".into(), Ty::NonNullUnknown);
        env.assigned.insert("value".into());
        let read = serde_json::json!({"kind":"DMASTDereference","file":"code/test.dm",
        "line":3,"fields":{
            "Expression":{"kind":"DMASTIdentifier","file":"code/test.dm",
                "line":3,"fields":{"Identifier":"value"}},
            "Operations":[{"kind":"FieldOperation","fields":{
                "Identifier":"name","Safe":false}}]
        }});
        checker.inspect_expr(&read, "/datum/test", &env);
        assert!(!checker
            .findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-member-read"));
        let unknown_call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Unknown"}},
            "Parameters":[]}});
        env.invalidate_after(&unknown_call);
        assert_eq!(env.facts["value"], Ty::Unknown);
    }

    #[test]
    fn short_circuit_type_guard_checks_member_on_narrowed_receiver() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.procs.insert(
            ("/obj/item/organ/external".into(), "flow_occluded".into()),
            Signature {
                parameters: Vec::new(),
                result: Ty::Num,
                result_required: true,
                inferred_nullable_result: false,
                path: "code/test.dm".into(),
                line: 1,
            },
        );
        let mut env = Env::default();
        env.slots
            .insert("E".into(), Ty::Path("/obj/item/organ/external".into()));
        env.facts
            .insert("E".into(), Ty::Path("/obj/item/organ".into()));
        env.assigned.insert("E".into());
        let expression = serde_json::json!({"kind":"DMASTAnd","file":"code/test.dm",
        "line":3,"fields":{
            "LHS":{"kind":"DMASTImplicitIsType","file":"code/test.dm","line":3,
                "fields":{"Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"E"}}}},
            "RHS":{"kind":"DMASTDereference","file":"code/test.dm","line":3,
                "fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"E"}},
                    "Operations":[{"kind":"CallOperation","fields":{
                        "Identifier":"flow_occluded","Parameters":[],"Safe":false}}]}}
        }});
        checker.inspect_expr(&expression, "/datum/test", &env);
        assert_eq!(checker.coverage.resolved_calls, 1);
        assert!(!checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-member-call"));
    }

    #[test]
    fn same_owner_parent_call_uses_previous_definition() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.proc_versions.insert(
            (
                "/datum/controller/global_vars".into(),
                "InitGlobalCache".into(),
            ),
            vec![
                Signature {
                    parameters: Vec::new(),
                    result: Ty::Num,
                    result_required: true,
                    inferred_nullable_result: false,
                    path: "code/test.dm".into(),
                    line: 19,
                },
                Signature {
                    parameters: Vec::new(),
                    result: Ty::Text,
                    result_required: true,
                    inferred_nullable_result: false,
                    path: "code/test.dm".into(),
                    line: 20,
                },
            ],
        );
        checker.current_proc_version = Some(1);
        assert_eq!(
            checker
                .parent_signature("/datum/controller/global_vars", "InitGlobalCache")
                .map(|signature| signature.result.clone()),
            Some(Ty::Num)
        );
        checker.current_proc_version = None;
        assert!(checker
            .parent_signature("/datum/controller/global_vars", "InitGlobalCache")
            .is_none());
    }

    #[test]
    fn stale_or_safe_field_read_is_optional() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.fields.insert(
            ("/datum/test".into(), "item".into()),
            FieldInfo {
                ty: Ty::Path("/obj/item".into()),
                explicit_type: true,
                evidence: Ty::Null,
                origin: serde_json::json!({}),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let mut read = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
            "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"item","Safe":false}}]}});
        let mut vars = HashMap::from([("src".into(), Ty::Path("/datum/test".into()))]);
        vars.insert(STALE_REFERENCES.into(), Ty::Num);
        assert_eq!(
            checker.expression(&read, &vars, "/datum/test"),
            Ty::parse("/obj/item?")
        );
        let mut scalar = checker.fields[&("/datum/test".into(), "item".into())].clone();
        scalar.ty = Ty::Num;
        checker
            .fields
            .insert(("/datum/test".into(), "count".into()), scalar);
        read["fields"]["Operations"][0]["fields"]["Identifier"] = Value::String("count".into());
        assert_eq!(
            checker.expression(&read, &vars, "/datum/test"),
            Ty::parse("num?")
        );
        read["fields"]["Operations"][0]["fields"]["Identifier"] = Value::String("item".into());
        vars.remove(STALE_REFERENCES);
        read["fields"]["Operations"][0]["fields"]["Safe"] = Value::Bool(true);
        assert_eq!(
            checker.expression(&read, &vars, "/datum/test"),
            Ty::parse("/obj/item?")
        );
        read["fields"]["Operations"][0]["fields"]["Safe"] = Value::Bool(false);
        vars.insert(STALE_REFERENCES.into(), Ty::Num);
        seed_guard_facts(&read, &mut vars, &checker, "/datum/test");
        narrow(&read, true, &mut vars);
        assert_eq!(
            checker.expression(&read, &vars, "/datum/test"),
            Ty::parse("/obj/item")
        );
        let unknown_call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Unknown"}},
            "Parameters":[]}});
        invalidate_after(&unknown_call, &mut vars);
        assert_eq!(
            checker.expression(&read, &vars, "/datum/test"),
            Ty::parse("/obj/item?")
        );
    }

    #[test]
    fn fresh_implicit_list_result_tracks_checked_index_writes() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let start = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTCallableSelf"},
                "RHS":{"kind":"DMASTList","fields":{"Values":[],"IsAList":false}}}}}});
        let write = |index: Value| {
            serde_json::json!({"kind":"DMASTProcStatementExpression",
            "fields":{"Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTDereference","fields":{
                    "Expression":{"kind":"DMASTCallableSelf"},
                    "Operations":[{"kind":"IndexOperation","fields":{
                        "Index":index,"Safe":false}}]}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":7}}}}}})
        };
        let read = serde_json::json!({"kind":"DMASTProcStatementReturn","fields":{
            "Value":{"kind":"DMASTCallableSelf"}}});
        let run = |statements: Vec<Value>| {
            let body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
                "Statements":statements}});
            let mut vars = HashMap::new();
            let mut slot = Ty::Null;
            let mut fresh = false;
            let mut fresh_locals = HashSet::new();
            checker
                .summarize_block(
                    &body,
                    "/datum/test",
                    "Build",
                    &mut vars,
                    &mut slot,
                    &mut fresh,
                    &mut fresh_locals,
                )
                .0
                .unwrap()
        };
        let literal = serde_json::json!({"kind":"DMASTConstantString","fields":{
            "Value":"count"}});
        assert!(
            matches!(run(vec![start.clone(), write(literal), read.clone()]),
            Ty::Record(fields) if fields.get("count") == Some(&(Ty::Num, false)))
        );
        let dynamic = serde_json::json!({"kind":"DMASTIdentifier","fields":{
            "Identifier":"dynamic_key"}});
        assert_eq!(
            run(vec![start.clone(), write(dynamic), read.clone()]),
            Ty::Unknown
        );
        let alias = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration","fields":{
            "Name":"other","Type":"/list","ValueType":null,"IsGlobal":false,
            "Value":{"kind":"DMASTCallableSelf"}}});
        assert_eq!(run(vec![start, alias, read]), Ty::Unknown);

        let local_start = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration","fields":{
            "Name":"items","Type":"/list","ValueType":null,"IsGlobal":false,
            "Value":{"kind":"DMASTList","fields":{"Values":[],"IsAList":false}}}});
        let material = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration","fields":{
            "Name":"new_mineral","Type":"/datum/material","ValueType":null,"IsGlobal":false,
            "Value":{"kind":"DMASTNewExpr","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"type"}},
                "Parameters":[]}}}});
        let key = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"lowertext"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantString","fields":{"Value":"Steel"}}}}]}});
        let local_write = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTDereference","fields":{
                    "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
                    "Operations":[{"kind":"IndexOperation","fields":{"Index":key,"Safe":false}}]}},
                "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"new_mineral"}}}}}});
        let loop_body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
            "Statements":[material, local_write]}});
        let loop_stmt = serde_json::json!({"kind":"DMASTProcStatementFor","fields":{
            "Expression1":{"kind":"DMASTExpressionIn","fields":{
                "LHS":{"kind":"DMASTVarDeclExpression","fields":{
                    "DeclPath":{"kind":"DMASTPath","fields":{"Path":"var/type"}}}},
                "RHS":{"kind":"DMASTProcCall","fields":{
                    "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"subtypesof"}},
                    "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                        "Value":{"kind":"DMASTConstantPath","fields":{"Value":{
                            "kind":"DMASTPath","fields":{"Path":"/datum/material"}}}}}}]}}}},
            "Expression2":null,"Expression3":null,
            "Conditional":null,"Body":loop_body}});
        let local_return = serde_json::json!({"kind":"DMASTProcStatementReturn","fields":{
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}}}});
        assert_eq!(
            run(vec![
                local_start.clone(),
                loop_stmt.clone(),
                local_return.clone()
            ]),
            Ty::Assoc(
                Box::new(Ty::Text),
                Box::new(Ty::Path("/datum/material".into()))
            )
        );
        let local_alias = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration","fields":{
            "Name":"other","Type":"/list","ValueType":null,"IsGlobal":false,
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}}}});
        assert_eq!(
            run(vec![local_start, loop_stmt, local_alias, local_return]),
            Ty::Unknown
        );
    }

    #[test]
    fn bare_return_uses_implicit_result_slot() {
        let contracts =
            crate::contracts::collect("// dm-health: returns num\n/datum/test/proc/Value()\n");
        let assignment = serde_json::json!({"kind":"DMASTProcStatementExpression",
        "file":"code/test.dm","line":2,"fields":{"Expression":{
            "kind":"DMASTAssign","file":"code/test.dm","line":2,"fields":{
                "LHS":{"kind":"DMASTCallableSelf"},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":7}}
            }
        }}});
        let bare_return = serde_json::json!({"kind":"DMASTProcStatementReturn",
            "file":"code/test.dm","line":3,"fields":{"Value":null}});
        for (statements, fails) in [
            (vec![assignment.clone(), bare_return.clone()], false),
            (vec![bare_return], true),
        ] {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
                "name":"Value","file":"code/test.dm","line":1,"parameters":[],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":statements}}});
            let source = proc.to_string();
            let (findings, _) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings.iter().any(|f| f.rule == "strict-type-assignment"),
                fails
            );
        }
    }

    #[test]
    fn loop_continue_does_not_poison_return_inference() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Move","file":"code/test.dm","line":1,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementFor","fields":{"Body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[
                    {"kind":"DMASTProcStatementContinue","fields":{}}
                ]}}}},
            {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":1}}}}
        ]}}});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"),
            "{findings:?}"
        );
    }

    #[test]
    fn tgui_input_list_uses_item_type_at_call_site() {
        let ui = serde_json::json!({"kind":"proc","owner":"/",
            "name":"tgui_input_list","file":"code/test.dm","line":1,
            "parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[]}}});
        let choice = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Choice","file":"code/test.dm","line":2,
        "parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementVarDeclaration","fields":{"Name":"items",
                "Type":{"kind":"DMASTPath","fields":{"Path":"/list"}},
                "ValueType":"anything","Value":{"kind":"DMASTList","fields":{
                    "Values":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                        "Value":{"kind":"DMASTConstantString","fields":{"Value":"one"}}}}]}}}},
            {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTProcCall","fields":{"Callable":{
                    "kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"tgui_input_list"}},
                    "Parameters":[null,null,null,{"kind":"DMASTCallParameter",
                        "fields":{"Key":null,"Value":{"kind":"DMASTIdentifier",
                            "fields":{"Identifier":"items"}}}}]}}}}
        ]}}});
        let input = format!("{ui}\n{choice}");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            findings
                .iter()
                .any(|finding| finding.rule == "unannotated-nullable-return"
                    && finding.message.contains("/datum/test/Choice")),
            "{findings:?}"
        );
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/test/Choice")),
            "{findings:?}"
        );
    }

    #[test]
    fn list2text_preserves_text_list_shape() {
        let helper = serde_json::json!({"kind":"proc","owner":"/","name":"list2text",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Join","file":"code/test.dm","line":2,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTProcCall","fields":{"Callable":{
                    "kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"list2text"}},
                    "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                        "Value":{"kind":"DMASTList","fields":{"Values":[
                            {"kind":"DMASTCallParameter","fields":{"Key":null,
                                "Value":{"kind":"DMASTConstantString","fields":{"Value":"one"}}}}
                        ]}}}}]}}}}
        ]}}});
        let input = format!("{helper}\n{caller}");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/test/Join")),
            "{findings:?}"
        );
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unannotated-nullable-return"
                    && finding.message.contains("/datum/test/Join")),
            "{findings:?}"
        );
        let mut numeric_caller = caller.clone();
        numeric_caller["name"] = Value::String("JoinNum".into());
        numeric_caller["body"]["fields"]["Statements"][0]["fields"]["Value"]["fields"]
            ["Parameters"][0]["fields"]["Value"]["fields"]["Values"][0]["fields"]["Value"] = serde_json::json!({"kind":"DMASTConstantInteger",
                "fields":{"Value":7}});
        let numeric_input = format!("{helper}\n{numeric_caller}");
        let (numeric_findings, _) = analyze(
            numeric_input.as_bytes(),
            numeric_input.as_bytes(),
            numeric_input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !numeric_findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/test/JoinNum")),
            "{numeric_findings:?}"
        );
        let mut named_caller = caller.clone();
        named_caller["name"] = Value::String("JoinNamed".into());
        named_caller["body"]["fields"]["Statements"][0]["fields"]["Value"]["fields"]
            ["Parameters"][0]["fields"]["Key"] =
            serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"ls"}});
        let named_input = format!("{helper}\n{named_caller}");
        let (named_findings, _) = analyze(
            named_input.as_bytes(),
            named_input.as_bytes(),
            named_input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !named_findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/test/JoinNamed")),
            "{named_findings:?}"
        );
    }

    #[test]
    fn list2text_literal_length_determines_result_without_element_type() {
        let helper = serde_json::json!({"kind":"proc","owner":"/","name":"list2text",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let call = |values: Vec<Value>| {
            serde_json::json!({"kind":"DMASTProcCall",
            "fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                "fields":{"Identifier":"list2text"}},"Parameters":[{
                "kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                    "kind":"DMASTList","fields":{"Values":values}}}}]}})
        };
        let item = |value: Value| {
            serde_json::json!({"kind":"DMASTCallParameter",
            "fields":{"Key":null,"Value":value}})
        };
        let unknown = serde_json::json!({"kind":"DMASTIdentifier",
            "fields":{"Identifier":"dynamic_value"}});
        let caller = |name: &str, value: Value| {
            serde_json::json!({"kind":"proc",
            "owner":"/datum/test","name":name,"file":"code/test.dm","line":2,
            "parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{
                "Statements":[{"kind":"DMASTProcStatementReturn","fields":{
                    "Value":value}}]}}})
        };
        let text = caller(
            "Many",
            call(vec![
                item(unknown),
                item(serde_json::json!({
            "kind":"DMASTConstantInteger","fields":{"Value":7}})),
            ]),
        );
        let empty = caller("Empty", call(vec![]));
        let null = caller(
            "Nullable",
            call(vec![item(serde_json::json!({
            "kind":"DMASTConstantNull","fields":{}}))]),
        );
        let input = format!("{helper}\n{text}\n{empty}\n{null}");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        for name in ["Many", "Empty"] {
            assert!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "unknown-return-type"
                        && finding.message.contains(&format!("/datum/test/{name}"))),
                "{findings:?}"
            );
        }
        // The raw singleton is null. With no non-null branch, its return
        // type has no provable base type and must remain unresolved.
        assert!(
            findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/test/Nullable")),
            "{findings:?}"
        );
    }

    #[test]
    fn sorting_helpers_keep_precise_input_list_shape() {
        let helper = |name: &str| {
            serde_json::json!({"kind":"proc","owner":"/",
            "name":name,"file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}})
        };
        let caller = |name: &str, helper_name: &str| {
            serde_json::json!({"kind":"proc",
            "owner":"/datum/test","name":name,"file":"code/test.dm","line":2,
            "parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{
                "Statements":[{"kind":"DMASTProcStatementReturn","fields":{
                    "Value":{"kind":"DMASTProcCall","fields":{"Callable":{
                        "kind":"DMASTCallableProcIdentifier","fields":{"Identifier":helper_name}},
                        "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                            "Value":{"kind":"DMASTList","fields":{"Values":[{
                                "kind":"DMASTCallParameter","fields":{"Key":null,
                                    "Value":{"kind":"DMASTConstantInteger","fields":{"Value":7}}}
                            }]}}}}]}}}}]}}})
        };
        let input = format!(
            "{}\n{}\n{}\n{}",
            helper("sortTim"),
            helper("sortList"),
            caller("Tim", "sortTim"),
            caller("List", "sortList")
        );
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        for name in ["Tim", "List"] {
            assert!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "unknown-return-type"
                        && finding.message.contains(&format!("/datum/test/{name}"))),
                "{findings:?}"
            );
        }
    }

    #[test]
    fn simple_collection_helper_instantiates_element_type_from_call() {
        let helper = |name: &str, copied: bool| {
            let parameter = serde_json::json!({"Name":"values","type":{
                "kind":"DMASTPath","fields":{"Path":"/list"}},
                "valueType":"anything","defaultValue":null});
            let ident = serde_json::json!({"kind":"DMASTIdentifier",
                "fields":{"Identifier":"values"}});
            let returned = if copied {
                serde_json::json!({"kind":"DMASTDereference","fields":{
                    "Expression":ident,"Operations":[{"kind":"CallOperation","fields":{
                        "Identifier":"Copy","Safe":false,"Parameters":[]}}]}})
            } else {
                ident
            };
            serde_json::json!({"kind":"proc","owner":"/","name":name,
            "file":"code/test.dm","line":1,"parameters":[parameter],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementReturn","fields":{"Value":returned}}
            ]}}})
        };
        let caller = |name: &str, target: &str| {
            serde_json::json!({"kind":"proc",
            "owner":"/datum/test","name":name,"file":"code/test.dm","line":2,
            "parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{
                "Statements":[{"kind":"DMASTProcStatementReturn","fields":{
                    "Value":{"kind":"DMASTProcCall","fields":{"Callable":{
                        "kind":"DMASTCallableProcIdentifier","fields":{"Identifier":target}},
                        "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                            "Value":{"kind":"DMASTList","fields":{"Values":[{
                                "kind":"DMASTCallParameter","fields":{"Key":null,
                                    "Value":{"kind":"DMASTConstantInteger","fields":{"Value":7}}}
                            }]}}}}]}}}}]}}})
        };
        let input = format!(
            "{}\n{}\n{}\n{}",
            helper("IdentityList", false),
            helper("CopyList", true),
            caller("IdentityUse", "IdentityList"),
            caller("CopyUse", "CopyList")
        );
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        for name in ["IdentityUse", "CopyUse"] {
            assert!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "unknown-return-type"
                        && finding.message.contains(&format!("/datum/test/{name}"))),
                "{findings:?}"
            );
        }
    }

    #[test]
    fn fresh_local_named_writes_keep_heterogeneous_record_shape() {
        let declaration = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":2,"fields":{"Name":"data",
                "Type":{"kind":"DMASTPath","fields":{"Path":"/list"}},
                "ValueType":"anything","IsGlobal":false,
                "Value":{"kind":"DMASTList","fields":{"Values":[]}}}});
        let write = |key: &str, value: Value| {
            serde_json::json!({
            "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
            "fields":{"Expression":{"kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTDereference","fields":{
                    "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"data"}},
                    "Operations":[{"kind":"IndexOperation","fields":{
                        "Index":{"kind":"DMASTConstantString","fields":{"Value":key}},
                        "Safe":false}}]}},"RHS":value}}}})
        };
        let read = |key: &str| {
            serde_json::json!({"kind":"DMASTDereference",
            "fields":{"Expression":{"kind":"DMASTIdentifier",
                "fields":{"Identifier":"data"}},"Operations":[{
                    "kind":"IndexOperation","fields":{"Index":{
                        "kind":"DMASTConstantString","fields":{"Value":key}},
                        "Safe":false}}]}})
        };
        let body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{
            "Statements":[declaration,
                write("name", serde_json::json!({"kind":"DMASTConstantString",
                    "fields":{"Value":"alpha"}})),
                write("count", serde_json::json!({"kind":"DMASTConstantInteger",
                    "fields":{"Value":7}})),
                {"kind":"DMASTProcStatementReturn","fields":{"Value":read("name")}}]}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
            "name":"Build","file":"code/test.dm","line":1,"parameters":[],"body":body});
        let input = proc.to_string();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unresolved-index-write"
                    || (finding.rule == "unknown-return-type"
                        && finding.message.contains("Build"))),
            "{findings:?}"
        );

        let mut dynamic = proc.clone();
        dynamic["name"] = Value::String("Dynamic".into());
        let dynamic_key = serde_json::json!({"kind":"DMASTIdentifier",
            "fields":{"Identifier":"unknown_key"}});
        let mut dynamic_write = write(
            "placeholder",
            serde_json::json!({
            "kind":"DMASTConstantInteger","fields":{"Value":8}}),
        );
        dynamic_write["fields"]["Expression"]["fields"]["LHS"]["fields"]["Operations"][0]
            ["fields"]["Index"] = dynamic_key;
        dynamic["body"]["fields"]["Statements"]
            .as_array_mut()
            .unwrap()
            .insert(3, dynamic_write);
        let input = dynamic.to_string();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("Dynamic")),
            "{findings:?}"
        );

        let mut aliased = proc;
        aliased["name"] = Value::String("Aliased".into());
        aliased["body"]["fields"]["Statements"]
            .as_array_mut()
            .unwrap()
            .insert(
                3,
                serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
                "fields":{"Name":"alias","Type":{"kind":"DMASTPath",
                    "fields":{"Path":"/list"}},"ValueType":"anything",
                    "IsGlobal":false,"Value":{"kind":"DMASTIdentifier",
                        "fields":{"Identifier":"data"}}}}),
            );
        let input = aliased.to_string();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("Aliased")),
            "{findings:?}"
        );

        let mut partial = aliased;
        partial["name"] = Value::String("Partial".into());
        partial["body"]["fields"]["Statements"]
            .as_array_mut()
            .unwrap()
            .remove(3);
        partial["body"]["fields"]["Statements"]
            .as_array_mut()
            .unwrap()
            .insert(
                3,
                write(
                    "name",
                    serde_json::json!({"kind":"DMASTIdentifier",
                "fields":{"Identifier":"unproved"}}),
                ),
            );
        partial["body"]["fields"]["Statements"][4]["fields"]["Value"] = read("count");
        let input = partial.to_string();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("Partial")),
            "{findings:?}"
        );

        let mut literal = partial;
        literal["name"] = Value::String("Literal".into());
        literal["body"]["fields"]["Statements"][0]["fields"]["Value"] = serde_json::json!({"kind":"DMASTList","fields":{"Values":[{
            "kind":"DMASTCallParameter","fields":{"Key":{
                "kind":"DMASTConstantString","fields":{"Value":"name"}},
                "Value":{"kind":"DMASTConstantString","fields":{"Value":"alpha"}}}}
        ]}});
        literal["body"]["fields"]["Statements"]
            .as_array_mut()
            .unwrap()
            .remove(1);
        let input = literal.to_string();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("Literal")),
            "{findings:?}"
        );
    }

    #[test]
    fn tgui_alert_text_buttons_have_nullable_text_result() {
        let helper = serde_json::json!({"kind":"proc","owner":"/","name":"tgui_alert",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let buttons = serde_json::json!({"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantString","fields":{"Value":"Yes"}}}},
            {"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantString","fields":{"Value":"No"}}}}
        ]}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Choice","file":"code/test.dm","line":2,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTProcCall","fields":{"Callable":{
                    "kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"tgui_alert"}},
                    "Parameters":[null,null,null,{"kind":"DMASTCallParameter","fields":{
                        "Key":null,"Value":buttons}}]}}}}
        ]}}});
        let input = format!("{helper}\n{caller}");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            findings
                .iter()
                .any(|finding| finding.rule == "unannotated-nullable-return"
                    && finding.message.contains("/datum/test/Choice returns text")),
            "{findings:?}"
        );
    }

    #[test]
    fn virtual_return_joins_void_base_with_numeric_override() {
        let base = serde_json::json!({"kind":"proc","owner":"/mob","name":"restrained",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementReturn","fields":{"Value":null}}
            ]}}});
        let child = serde_json::json!({"kind":"proc","owner":"/mob/living",
        "name":"restrained","file":"code/test.dm","line":3,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                    "kind":"DMASTConstantInteger","fields":{"Value":1}}}}
            ]}}});
        let mut checker = Checker {
            symbols: &Symbols::default(),
            contracts: &[],
            selection: &Selection {
                all: true,
                ..Selection::default()
            },
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.register(&base);
        checker.register(&child);
        checker.infer_returns();
        assert_eq!(
            checker.procs[&("/mob".into(), "restrained".into())].result,
            Ty::parse("num?")
        );
        assert_eq!(
            checker.procs[&("/mob/living".into(), "restrained".into())].result,
            Ty::Num
        );
    }

    #[test]
    fn returned_assignment_has_rhs_type() {
        let returned = serde_json::json!({"kind":"DMASTProcStatementReturn",
        "fields":{"Value":{"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"library"}},
            "RHS":{"kind":"DMASTTernary","fields":{
                "A":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "B":{"kind":"DMASTConstantString","fields":{"Value":"libverdigris"}},
                "C":{"kind":"DMASTConstantString","fields":{"Value":"verdigris"}}
            }}
        }}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/","name":"detect",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[returned]}}});
        let mut checker = Checker {
            symbols: &Symbols::default(),
            contracts: &[],
            selection: &Selection {
                all: true,
                ..Selection::default()
            },
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.register(&proc);
        checker.infer_returns();
        assert_eq!(
            checker.procs[&("/".into(), "detect".into())].result,
            Ty::Text
        );
    }

    #[test]
    fn typed_field_new_infers_the_created_path() {
        let mut checker = Checker {
            symbols: &Symbols::default(),
            contracts: &[],
            selection: &Selection {
                all: true,
                ..Selection::default()
            },
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let key = ("/atom".into(), "forensic_data".into());
        checker.fields.insert(
            key.clone(),
            FieldInfo {
                ty: Ty::Path("/datum/forensics_crime".into()),
                explicit_type: true,
                evidence: Ty::Null,
                origin: serde_json::json!({}),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: true,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let write = serde_json::json!({"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"forensic_data"}},
            "RHS":{"kind":"DMASTNewInferred","fields":{"Parameters":[]}}
        }});
        checker.register_writes(&write, "/atom", &HashMap::new(), &HashSet::new());
        assert_eq!(
            checker.fields[&key].evidence,
            Ty::Path("/datum/forensics_crime".into())
        );
        assert!(!checker.fields[&key].saw_unknown_write);
    }

    #[test]
    fn boolean_normalization_proves_escaped_result_type() {
        let unknown_index = serde_json::json!({"kind":"DMASTIndex","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"result_box"}},
            "Index":{"kind":"DMASTConstantString","fields":{"Value":"success"}}
        }});
        let normalized = serde_json::json!({"kind":"DMASTNot","fields":{"Value":{
            "kind":"DMASTNot","fields":{"Value":unknown_index}}
        }});
        let compat = serde_json::json!({"kind":"proc","owner":"/",
        "name":"om_do_after_compat","file":"code/test.dm","line":1,
        "parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{
            "Statements":[{"kind":"DMASTProcStatementReturn","fields":{"Value":normalized}}]
        }}});
        let call = serde_json::json!({"kind":"DMASTProcCall","fields":{"Callable":{
            "kind":"DMASTCallableProcIdentifier",
            "fields":{"Identifier":"om_do_after_compat"}},"Parameters":[]}});
        let forward = serde_json::json!({"kind":"proc","owner":"/","name":"do_after",
        "file":"code/test.dm","line":2,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementReturn","fields":{"Value":call}}
            ]}}});
        let mut checker = Checker {
            symbols: &Symbols::default(),
            contracts: &[],
            selection: &Selection {
                all: true,
                ..Selection::default()
            },
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.register(&forward);
        checker.register(&compat);
        checker.infer_returns();
        assert_eq!(
            checker.procs[&("/".into(), "om_do_after_compat".into())].result,
            Ty::Num
        );
        assert_eq!(
            checker.procs[&("/".into(), "do_after".into())].result,
            Ty::Num
        );
    }

    #[test]
    fn timer_id_union_keeps_field_conflict_and_return_shape() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let key = ("/datum/timedevent".into(), "id".into());
        checker.fields.insert(
            key.clone(),
            FieldInfo {
                ty: Ty::Unknown,
                explicit_type: false,
                evidence: Ty::Null,
                origin: serde_json::json!({"kind":"field","file":"code/test.dm","line":1}),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: true,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        checker.merge_field_write(&key, Ty::Num);
        checker.merge_field_write(&key, Ty::Text);
        checker.finalize_fields();
        assert_eq!(checker.fields[&key].ty, Ty::parse("oneof<num,text>"));
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "field-type-conflict"));
        assert_eq!(checker.coverage.unresolved_declarations, 1);

        let num = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":-1}});
        let text = serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"42"}});
        let proc = serde_json::json!({"kind":"proc","owner":"/","name":"_addtimer",
        "file":"code/test.dm","line":2,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementIf","fields":{
                    "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                    "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                        {"kind":"DMASTProcStatementReturn","fields":{"Value":text}}
                    ]}},"ElseBody":null}},
                {"kind":"DMASTProcStatementIf","fields":{
                    "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                    "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                        {"kind":"DMASTProcStatementReturn","fields":{"Value":null}}
                    ]}},"ElseBody":null}},
                {"kind":"DMASTProcStatementReturn","fields":{"Value":num}}
            ]}}});
        checker.register(&proc);
        checker.infer_returns();
        assert_eq!(
            checker.procs[&("/".into(), "_addtimer".into())].result,
            Ty::parse("oneof<num,text>?")
        );
        let guard = serde_json::json!({"kind":"DMASTIsType","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"hash_timer"}},
            "RHS":{"kind":"DMASTConstantPath","fields":{"Value":{
                "kind":"DMASTPath","fields":{"Path":"/datum/timedevent"}}}}
        }});
        let id = serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"hash_timer"}},
            "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"id","Safe":false}}]
        }});
        let mut vars = HashMap::from([("hash_timer".into(), Ty::Unknown)]);
        assert_eq!(checker.expression(&id, &vars, "/"), Ty::Unknown);
        narrow(&guard, true, &mut vars);
        assert_eq!(
            checker.expression(&id, &vars, "/"),
            Ty::parse("oneof<num,text>")
        );
        let typed_return = |guard_name: &str| {
            serde_json::json!({
                "kind":"DMASTProcStatementIf","fields":{
                    "Condition":{"kind":"DMASTProcCall","fields":{
                        "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":guard_name}},
                        "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"new_id"}}}}]
                    }},
                    "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
                        "kind":"DMASTProcStatementReturn","fields":{"Value":{
                            "kind":"DMASTIdentifier","fields":{"Identifier":"new_id"}}}}
                    ]}},"ElseBody":null
                }
            })
        };
        let checked = serde_json::json!({"kind":"proc","owner":"/","name":"checked_timer_id",
        "file":"code/test.dm","line":10,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementVarDeclaration","fields":{"Name":"new_id",
                    "Type":null,"ValueType":"anything","Value":{
                        "kind":"DMASTIdentifier","fields":{"Identifier":"unknown_id"}}}},
                typed_return("isnum"), typed_return("istext")
            ]}}});
        checker.register(&checked);
        checker.infer_returns();
        assert_eq!(
            checker.procs[&("/".into(), "checked_timer_id".into())].result,
            Ty::parse("oneof<num,text>?")
        );
    }

    #[test]
    fn nullable_return_union_reaches_a_fixed_point() {
        let symbols = Symbols::default();
        let expected = Ty::parse("oneof<num,text>?");
        let mut current = Ty::Num;
        for _ in 0..64 {
            current = join_value_flow(&current, &Ty::Text, &symbols);
            current = join_value_flow(&current, &Ty::Null, &symbols);
            current = join_value_flow(&current, &expected, &symbols);
            assert_eq!(current, expected);
        }
        let nested = Ty::Nullable(Box::new(expected.clone()));
        assert_eq!(join_value_flow(&nested, &Ty::Num, &symbols), expected);
    }

    #[test]
    fn fresh_override_literal_checks_each_entry_against_wider_contract() {
        let contracts = crate::contracts::collect(
            "// dm-health: type assoc<typepath</datum/symptom>,num>?\n/datum/test/var/list/symptoms\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"symptoms",
            "file":"code/test.dm","line":1,"type":"/list","valueType":null,"initializer":null});
        let override_with = |value: Value| {
            serde_json::json!({"kind":"field-override",
            "owner":"/datum/test/child","name":"symptoms","file":"code/test.dm","line":3,
            "initializer":{"kind":"DMASTList","fields":{"Values":[
                {"kind":"DMASTCallParameter","fields":{
                        "Key":{"kind":"DMASTConstantPath","fields":{"Value":{
                            "kind":"DMASTPath","fields":{"Path":"/datum/symptom/child"}}}},
                    "Value":value}}]}}})
        };
        for (value, should_fail) in [
            (
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
                false,
            ),
            (
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"bad"}}),
                true,
            ),
        ] {
            let source = format!("{field}\n{}\n", override_with(value));
            let (findings, coverage) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "strict-type-assignment"),
                should_fail
            );
            if !should_fail {
                assert!(
                    coverage.checked_assignments > 0,
                    "{findings:?} {coverage:?}"
                );
            }
        }
        assert!(!Ty::parse("assoc<typepath</datum/symptom>,num>").accepts(
            &Ty::parse("assoc<typepath</datum/symptom/child>,num>"),
            &Symbols::default()
        ));
    }

    #[test]
    fn declared_field_initializer_is_checked_against_its_contract() {
        let contracts = crate::contracts::collect(
            "// dm-health: type assoc<typepath</datum/symptom>,num>\n/datum/test/var/list/symptoms\n",
        );
        let literal_with = |value: Value| {
            serde_json::json!({"kind":"DMASTList","fields":{
            "Values":[{"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/datum/symptom/child"}}}},
                "Value":value}}]}})
        };
        for (value, should_fail) in [
            (
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
                false,
            ),
            (
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"bad"}}),
                true,
            ),
        ] {
            let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"symptoms",
                "file":"code/test.dm","line":1,"type":"/list","valueType":null,
                "initializer":literal_with(value)});
            let source = format!("{field}\n");
            let (findings, coverage) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "strict-type-assignment"),
                should_fail,
                "{findings:?}"
            );
            if !should_fail {
                assert!(coverage.checked_assignments > 0);
            }
        }
    }

    #[test]
    fn fresh_literal_argument_checks_each_entry_against_parameter_contract() {
        let contracts = crate::contracts::collect(
            "// dm-health: param symptoms assoc<typepath</datum/symptom>,num>\n/datum/test/proc/Take(list/symptoms)\n",
        );
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Take",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"symptoms",
                "type":"/list","valueType":null,"defaultValue":null}],"body":null});
        for (value, should_fail) in [
            (
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
                false,
            ),
            (
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"bad"}}),
                true,
            ),
        ] {
            let literal = serde_json::json!({"kind":"DMASTList","fields":{"Values":[
                {"kind":"DMASTCallParameter","fields":{
                    "Key":{"kind":"DMASTConstantPath","fields":{"Value":{
                        "kind":"DMASTPath","fields":{"Path":"/datum/symptom/child"}}}},
                    "Value":value}}
            ]}});
            let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                    "fields":{"Expression":{"kind":"DMASTProcCall","file":"code/test.dm","line":3,
                        "fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                            "fields":{"Identifier":"Take"}},
                            "Parameters":[{"kind":"DMASTCallParameter","file":"code/test.dm","line":3,
                                "fields":{"Key":null,"Value":literal}}]}}}}
                ]}}});
            let source = format!("{target}\n{caller}\n");
            let (findings, coverage) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "strict-type-assignment"),
                should_fail,
                "{findings:?}"
            );
            if !should_fail {
                assert!(coverage.checked_assignments > 0);
            }
        }
    }

    #[test]
    fn fresh_record_argument_checks_optional_keys_and_nested_values() {
        let schema = "record<factors?:alist<num,num>,always_spawns?:list<typepath</datum/affliction>>,organ_damage_type?:oneof<num,text>>";
        let parsed = Ty::parse(schema);
        assert!(matches!(parsed, Ty::Record(_)));
        assert!(parsed.is_precise());
        let choice = Ty::parse("oneof<num,text>");
        assert!(choice.accepts(&Ty::Num, &Symbols::default()));
        assert!(choice.accepts(&Ty::Text, &Symbols::default()));
        assert!(!choice.accepts(&Ty::Null, &Symbols::default()));
        let contracts = crate::contracts::collect(&format!(
            "// dm-health: param extra {schema}\n/datum/test/proc/Use(list/extra)\n"
        ));
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Use",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"extra",
                "type":"/list","valueType":null,"defaultValue":null}],"body":null});
        let alist = serde_json::json!({"kind":"DMASTList","fields":{"IsAList":true,"Values":[
            {"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":2}}}}
        ]}});
        let paths = serde_json::json!({"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{"Key":null,
                "Value":{"kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/datum/affliction/child"}}}}}}
        ]}});
        let entry = |key: &str, value: Value| {
            serde_json::json!({"kind":"DMASTCallParameter",
            "fields":{"Key":{"kind":"DMASTConstantString","fields":{"Value":key}},
                "Value":value}})
        };
        for (entries, should_fail) in [
            (
                vec![
                    entry("factors", alist.clone()),
                    entry("always_spawns", paths.clone()),
                    entry(
                        "organ_damage_type",
                        serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":8}}),
                    ),
                ],
                false,
            ),
            (
                vec![entry(
                    "organ_damage_type",
                    serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"internal"}}),
                )],
                false,
            ),
            (
                vec![
                    entry("factors", alist.clone()),
                    entry("unexpected", paths.clone()),
                ],
                true,
            ),
        ] {
            let literal = serde_json::json!({"kind":"DMASTList","fields":{"Values":entries}});
            let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                    "fields":{"Expression":{"kind":"DMASTProcCall","file":"code/test.dm","line":3,
                        "fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                            "fields":{"Identifier":"Use"}},
                            "Parameters":[{"kind":"DMASTCallParameter","file":"code/test.dm","line":3,
                                "fields":{"Key":null,"Value":literal}}]}}}}
                ]}}});
            let source = format!("{target}\n{caller}\n");
            let (findings, coverage) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            if should_fail {
                assert!(
                    findings.iter().any(|finding| matches!(
                        finding.rule,
                        "strict-type-assignment" | "unknown-type-flow"
                    )),
                    "{findings:?}"
                );
            } else {
                assert!(
                    !findings.iter().any(|finding| matches!(
                        finding.rule,
                        "strict-type-assignment" | "unknown-type-flow"
                    )),
                    "{findings:?}"
                );
                assert!(coverage.checked_assignments > 0);
            }
        }
    }

    #[test]
    fn comment_type_aliases_expand_nested_schemas_and_reject_cycles() {
        let contracts = crate::contracts::collect(
            "// dm-health: alias Stage = record<value:num>\n\
             // dm-health: alias Stages = assoc<text,@Stage>\n\
             // dm-health: param stages @Stages\n/datum/test/proc/Use(list/stages)\n",
        );
        assert_eq!(
            annotated_type(
                &contracts,
                "/datum/test",
                "Use",
                Visibility::ParamType,
                Some("stages")
            ),
            Some(Ty::parse("assoc<text,record<value:num>>"))
        );
        let cycle = crate::contracts::collect(
            "// dm-health: alias A = @B\n// dm-health: alias B = @A\n\
             // dm-health: param value @A\n/datum/test/proc/Use(value)\n",
        );
        assert_eq!(
            annotated_type(
                &cycle,
                "/datum/test",
                "Use",
                Visibility::ParamType,
                Some("value")
            ),
            Some(Ty::Unknown)
        );
        assert_eq!(
            Ty::parse("merge<record<value:num>,record<note?:text>>"),
            Ty::parse("record<value:num,note?:text>")
        );
        assert_eq!(
            Ty::parse("merge<record<value:num>,record<value:text>>"),
            Ty::Unknown
        );
        let medical = crate::contracts::collect(include_str!(
            "../../../code/modules/medical/conditions/pharmacology/_pharmacology.dm"
        ));
        let stage = annotated_type(
            &medical,
            "/",
            "overdose_stages",
            Visibility::ParamType,
            Some("mild"),
        )
        .unwrap();
        assert!(matches!(&stage, Ty::Record(fields) if fields.len() == 10
            && fields.get("min_symptoms") == Some(&(Ty::parse("num?"), false))));
        assert_eq!(
            annotated_type(
                &medical,
                "/",
                "overdose_stages",
                Visibility::ReturnType,
                None
            ),
            Some(Ty::Assoc(
                Box::new(Ty::Text),
                Box::new(Ty::Nullable(Box::new(stage)))
            ))
        );
    }

    #[test]
    fn record_builder_inference_requires_correlated_copy_key() {
        let contracts = crate::contracts::collect(
            "// dm-health: param extra record<note?:text>?\n/datum/test/proc/Build(value, list/extra)\n",
        );
        let index = |receiver: Value, key: &str| {
            serde_json::json!({
            "kind":"DMASTDereference","fields":{"Expression":receiver,
                "Operations":[{"kind":"IndexOperation","fields":{
                    "Index":{"kind":"DMASTIdentifier","fields":{"Identifier":key}},
                    "Safe":false}}]}})
        };
        let base = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
        "Expression":{"kind":"DMASTAssign","fields":{
            "LHS":{"kind":"DMASTCallableSelf"},
            "RHS":{"kind":"DMASTList","fields":{"Values":[
                {"kind":"DMASTCallParameter","fields":{
                    "Key":{"kind":"DMASTConstantString","fields":{"Value":"value"}},
                    "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}}}}
            ]}}}}}});
        for (read_key, proved) in [("key", true), ("different", false)] {
            let copy = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTAssign","fields":{
                "LHS":index(serde_json::json!({"kind":"DMASTCallableSelf"}), "key"),
                "RHS":index(serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"extra"}}), read_key)
            }}}});
            let loop_statement = serde_json::json!({"kind":"DMASTProcStatementFor","fields":{
                "Expression1":{"kind":"DMASTExpressionIn","fields":{
                    "LHS":{"kind":"DMASTVarDeclExpression","fields":{
                        "DeclPath":{"kind":"DMASTPath","fields":{"Path":"var/key"}}}},
                    "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"extra"}}}},
                "Expression2":null,"Expression3":null,"DMTypes":null,
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[copy],"SetStatements":[]}}
            }});
            let conditional = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
                "Condition":{"kind":"DMASTIdentifier","fields":{"Identifier":"extra"}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[loop_statement],"SetStatements":[]}},
                "ElseBody":null}});
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Build",
                "file":"code/test.dm","line":1,
                "parameters":[
                    {"Name":"value","type":null,"valueType":"num","defaultValue":null},
                    {"Name":"extra","type":"/list","valueType":null,"defaultValue":null}
                ],"body":{"kind":"DMASTProcBlockInner","fields":{
                    "Statements":[base.clone(),conditional],"SetStatements":[]}}});
            let source = format!("{proc}\n");
            let (findings, _) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "unknown-return-type"),
                proved,
                "{findings:?}"
            );
            if proved {
                assert!(
                    !findings.iter().any(|finding| matches!(
                        finding.rule,
                        "unknown-type-flow" | "unresolved-index" | "unresolved-index-write"
                    )),
                    "{findings:?}"
                );
            }
        }
    }

    #[test]
    fn compatible_literal_overrides_do_not_create_false_field_conflict() {
        let contracts = crate::contracts::collect(
            "// dm-health: type assoc<typepath</datum/symptom>,num>?\n/datum/test/var/list/symptoms\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"symptoms",
        "file":"code/test.dm","line":1,"type":"/list","valueType":null,
        "initializer":{"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/datum/symptom/base"}}}},
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}
        ]}}});
        let override_for = |owner: &str, path: &str| {
            serde_json::json!({
            "kind":"field-override","owner":owner,"name":"symptoms",
            "file":"code/test.dm","line":3,
            "initializer":{"kind":"DMASTList","fields":{"Values":[
                {"kind":"DMASTCallParameter","fields":{
                    "Key":{"kind":"DMASTConstantPath","fields":{"Value":{
                        "kind":"DMASTPath","fields":{"Path":path}}}},
                    "Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}
            ]}}})
        };
        let source = format!(
            "{field}\n{}\n{}\n",
            override_for("/datum/test/a", "/datum/symptom/a"),
            override_for("/datum/test/b", "/datum/symptom/b")
        );
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "field-type-conflict"),
            "{findings:?}"
        );
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "strict-type-assignment"),
            "{findings:?}"
        );
        assert_eq!(coverage.checked_assignments, 3);
    }

    #[test]
    fn compatible_fresh_literal_field_write_preserves_declared_collection_type() {
        let contracts = crate::contracts::collect(
            "// dm-health: type assoc<typepath</datum/symptom>,num>?\n/datum/test/var/list/symptoms\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"symptoms",
            "file":"code/test.dm","line":1,"type":"/list","valueType":null,"initializer":null});
        let literal = serde_json::json!({"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantPath","fields":{"Value":{
                    "kind":"DMASTPath","fields":{"Path":"/datum/symptom/child"}}}},
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}
        ]}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Set",
        "file":"code/test.dm","line":2,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                "fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm","line":3,
                    "fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"symptoms"}},
                    "RHS":literal}}}
            }]}}});
        let source = format!("{field}\n{proc}\n");
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "field-type-conflict"
                    || finding.rule == "strict-type-assignment"),
            "{findings:?}"
        );
        assert!(coverage.checked_assignments > 0);
    }

    #[test]
    fn chained_field_index_write_checks_element_instead_of_whole_field() {
        let contracts = crate::contracts::collect(
            "// dm-health: type assoc<text,num>?\n/datum/test/var/list/values\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"values",
            "file":"code/test.dm","line":1,"type":"/list","valueType":null,"initializer":null});
        for (index, value, should_fail) in [
            (
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"x"}}),
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
                false,
            ),
            (
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
                serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":1}}),
                true,
            ),
            (
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"x"}}),
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"bad"}}),
                true,
            ),
        ] {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Set",
            "file":"code/test.dm","line":2,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[
                    {"kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                     "fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm","line":3,
                       "fields":{"LHS":{"kind":"DMASTDereference","fields":{
                         "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
                         "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"values","Safe":false}}]}},
                         "RHS":{"kind":"DMASTList","fields":{"Values":[]}}}}}},
                    {
                    "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":3,
                    "fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm","line":3,
                        "fields":{"LHS":{"kind":"DMASTDereference","fields":{
                            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
                            "Operations":[
                                {"kind":"FieldOperation","fields":{"Identifier":"values","Safe":false}},
                                {"kind":"IndexOperation","fields":{"Index":index,"Safe":false}}
                            ]}},"RHS":value}}}
                }]}}});
            let source = format!("{field}\n{proc}\n");
            let (findings, _) = analyze(
                source.as_bytes(),
                source.as_bytes(),
                source.as_bytes(),
                &Symbols::default(),
                &contracts,
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "strict-type-assignment"),
                should_fail,
                "{findings:?}"
            );
            assert!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "field-type-conflict"),
                "{findings:?}"
            );
            assert!(
                !findings
                    .iter()
                    .any(|finding| finding.rule == "unresolved-index-write"),
                "{findings:?}"
            );
        }
    }

    #[test]
    fn unknown_literal_entry_does_not_discharge_collection_contract() {
        let contracts = crate::contracts::collect(
            "// dm-health: type assoc<text,num>\n/datum/test/var/list/values\n",
        );
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"values",
        "file":"code/test.dm","line":1,"type":"/list","valueType":null,
        "initializer":{"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantString","fields":{"Value":"x"}},
                "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"unknown_value"}}}}
        ]}}});
        let source = format!("{field}\n");
        let (findings, coverage) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-type-flow"));
        assert_eq!(coverage.checked_assignments, 0);
        assert!(coverage.unresolved_assignments > 0);
    }

    #[test]
    fn checked_list_rejects_wrong_element_and_nullable_lookup() {
        let contracts = crate::contracts::collect(
            "// dm-health: param values list<num>\n/datum/test/proc/Read(values)\n",
        );
        let index = serde_json::json!({"kind":"DMASTDereference","file":"code/test.dm",
            "line":2,"fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"values"}},
            "Operations":[{"kind":"IndexOperation","fields":{"Index":{
                "kind":"DMASTConstantInteger","fields":{"Value":1}},"Safe":false}}]}});
        let write = serde_json::json!({"kind":"DMASTProcStatementExpression","file":"code/test.dm",
            "line":2,"fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm",
            "line":2,"fields":{"LHS":index.clone(),"RHS":{"kind":"DMASTConstantString",
            "fields":{"Value":"bad"}}}}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Read",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"values","type":null,
            "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[write]}}});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|f| f.rule == "strict-type-assignment" && f.message.contains("list element")));
        let mut checker = Checker {
            symbols: &Symbols::default(),
            contracts: &[],
            selection: &Selection::default(),
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let vars = HashMap::from([("values".into(), Ty::parse("list<num>"))]);
        assert_eq!(
            checker.expression(&index, &vars, "/datum/test"),
            Ty::parse("num?")
        );
        checker.findings.clear();
        let keyed = serde_json::json!({"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantString","fields":{"Value":"one"}},
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}},
            {"kind":"DMASTCallParameter","fields":{
                "Key":{"kind":"DMASTConstantString","fields":{"Value":"two"}},
                "Value":{"kind":"DMASTConstantInteger","fields":{"Value":2}}}}
        ]}});
        assert_eq!(
            checker.expression(&keyed, &HashMap::new(), "/datum/test"),
            Ty::parse("assoc<text,num>")
        );
    }

    #[test]
    fn incompatible_branch_writes_cannot_infer_one_local_type() {
        let local = serde_json::json!({"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":2,"fields":{"Name":"slot","Type":null,
            "ValueType":"anything","Value":null}});
        let write = |value: Value| {
            serde_json::json!({"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression",
            "file":"code/test.dm","line":4,"fields":{"Expression":{
                "kind":"DMASTAssign","file":"code/test.dm","line":4,"fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"slot"}},
                    "RHS":value}}}}]}})
        };
        let branch = serde_json::json!({"kind":"DMASTProcStatementIf",
        "file":"code/test.dm","line":3,"fields":{
            "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "Body":write(serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":3}})),
            "ElseBody":write(serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"x"}}))
        }});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[local,branch]}}});
        let source = proc.to_string();
        let (findings, _) = analyze(
            source.as_bytes(),
            source.as_bytes(),
            source.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings.iter().any(|f| f.rule == "local-type-conflict"));
    }

    #[test]
    fn return_inference_reaches_caller_and_rejects_null_path() {
        let value = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Value",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":2,
                "fields":{"Value":{"kind":"DMASTConstantInteger","fields":{"Value":4}}}
            }]}}});
        let call = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Value"}},
            "Parameters":[]}});
        let forwarding = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Forward",
        "file":"code/test.dm","line":4,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementReturn","file":"code/test.dm","line":5,
                "fields":{"Value":call}
            }]}}});
        let partial = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Partial",
        "file":"code/test.dm","line":6,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementIf","file":"code/test.dm","line":7,
                "fields":{"Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementReturn","fields":{"Value":{
                        "kind":"DMASTConstantInteger","fields":{"Value":3}}}}]}},
                "ElseBody":null}
            }]}}});
        let input = [forwarding, partial, value]
            .iter()
            .map(Value::to_string)
            .collect::<Vec<_>>()
            .join("\n");
        let mut checker = Checker {
            symbols: &Symbols::default(),
            contracts: &[],
            selection: &Selection {
                all: true,
                ..Selection::default()
            },
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        for line in input.lines() {
            checker.register(&serde_json::from_str::<Value>(line).unwrap());
        }
        checker.infer_returns();
        assert_eq!(
            checker.procs[&("/datum/test".into(), "Forward".into())].result,
            Ty::Num
        );
        assert_eq!(
            checker.procs[&("/datum/test".into(), "Partial".into())].result,
            Ty::parse("num?")
        );
    }

    #[test]
    fn implicit_result_assignment_from_parent_keeps_inferred_return() {
        let parent = serde_json::json!({"kind":"proc","owner":"/datum/base","name":"Notify",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let child = serde_json::json!({"kind":"proc","owner":"/datum/base/child","name":"Notify",
        "file":"code/test.dm","line":3,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementExpression","fields":{"Expression":{
                    "kind":"DMASTAssign","fields":{
                        "LHS":{"kind":"DMASTCallableSelf"},
                        "RHS":{"kind":"DMASTProcCall","fields":{
                            "Callable":{"kind":"DMASTCallableSuper"},"Parameters":[]}}
                    }}}}]}}});
        let input = format!("{parent}\n{child}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/base/child/Notify")),
            "{findings:?}"
        );
    }

    #[test]
    fn parent_virtual_return_is_promoted_after_child_inference() {
        let procedure = |owner: &str| {
            serde_json::json!({
                "kind":"proc","owner":owner,"name":"Notify","file":"code/test.dm",
                "line":1,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
                    "fields":{"Statements":[]}}
            })
        };
        let input = format!(
            "{}\n{}\n",
            procedure("/datum/base/child"),
            procedure("/datum/base")
        );
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    && finding.message.contains("/datum/base/Notify")),
            "{findings:?}"
        );
    }

    #[test]
    fn nullable_return_keeps_type_and_requires_contract() {
        let returning = |value: Value| {
            serde_json::json!({
                "kind":"DMASTProcStatementReturn","fields":{"Value":value}
            })
        };
        let num = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":7}});
        let null = serde_json::json!({"kind":"DMASTConstantNull","fields":{}});
        let branch = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
            "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[returning(num)]}},
            "ElseBody":{"kind":"DMASTProcBlockInner","fields":{"Statements":[returning(null)]}}
        }});
        let procedure = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Maybe",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[branch]}}});
        let input = format!("{procedure}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            findings
                .iter()
                .any(|finding| finding.rule == "unannotated-nullable-return"),
            "{findings:?}"
        );
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    || finding.rule == "unknown-type-flow"),
            "{findings:?}"
        );
        let contracts =
            crate::contracts::collect("// dm-health: nullable\n/datum/test/proc/Maybe()\n");
        let (annotated, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !annotated
                .iter()
                .any(|finding| finding.rule == "unannotated-nullable-return"),
            "{annotated:?}"
        );
    }

    #[test]
    fn explicit_return_of_implicit_result_slot_uses_assigned_type() {
        let procedure = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Label",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                    "kind":"DMASTAssign","fields":{
                        "LHS":{"kind":"DMASTCallableSelf"},
                        "RHS":{"kind":"DMASTConstantString","fields":{"Value":"ready"}}
                    }}}},
                {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                    "kind":"DMASTCallableSelf"}}}
            ]}}});
        let input = format!("{procedure}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(
            !findings
                .iter()
                .any(|finding| finding.rule == "unknown-return-type"
                    || finding.rule == "unknown-type-flow"),
            "{findings:?}"
        );
    }

    #[test]
    fn spawned_return_does_not_define_enclosing_result() {
        let spawned = serde_json::json!({"kind":"DMASTProcStatementSpawn","fields":{
        "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":7}}}},
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTCallableSelf"},
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
                }}}}
        ]}}}});
        assert!(!has_explicit_value_return(&spawned));
        assert!(!has_implicit_result_assignment(&spawned));
    }

    #[test]
    fn inferred_base_return_requires_compatible_overrides() {
        let procedure = |owner: &str, value: Value| {
            serde_json::json!({"kind":"proc","owner":owner,"name":"Value",
            "file":"code/test.dm","line":1,"parameters":[],"body":{
                "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                    "kind":"DMASTProcStatementReturn","fields":{"Value":value}
                }]}}})
        };
        let num = serde_json::json!({"kind":"DMASTConstantInteger","fields":{"Value":7}});
        let text = serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"wrong"}});
        for (override_value, expected) in [(num.clone(), false), (text, true)] {
            let input = format!(
                "{}\n{}\n",
                procedure("/datum/base", num.clone()),
                procedure("/datum/base/child", override_value)
            );
            let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
            let (findings, _) = analyze(
                input.as_bytes(),
                input.as_bytes(),
                input.as_bytes(),
                &symbols,
                &[],
                &Selection {
                    all: true,
                    ..Selection::default()
                },
            )
            .unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "unknown-return-type"
                        && finding.message.contains("/datum/base/Value")),
                expected
            );
        }
    }

    #[test]
    fn repeated_proc_definition_infers_previous_version_return() {
        let first = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Value","file":"code/test.dm","line":1,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
            "kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":4}}}
        }]}}});
        let second = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Value","file":"code/test.dm","line":5,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
            "kind":"DMASTProcStatementReturn","fields":{"Value":{
                "kind":"DMASTProcCall","fields":{"Callable":{
                    "kind":"DMASTCallableSuper"},"Parameters":[]}}}
        }]}}});
        let input = format!("{first}\n{second}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-return-type"
                && finding.message.contains("/datum/test/Value")));
    }

    #[test]
    fn precise_default_infers_parameter_but_null_default_does_not() {
        let make = |name: &str, default: Value| {
            serde_json::json!({
                "kind":"proc","owner":"/datum/test","name":name,
                "file":"code/test.dm","line":1,
                "parameters":[{"Name":"amount","type":null,"valueType":null,
                    "defaultValue":default}],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}
            })
        };
        let numeric = make(
            "Numeric",
            serde_json::json!({
            "kind":"DMASTConstantInteger","fields":{"Value":3}}),
        );
        let optional = make(
            "Optional",
            serde_json::json!({
            "kind":"DMASTConstantNull"}),
        );
        let input = format!("{numeric}\n{optional}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-parameter-type"
                && finding.message.contains("Numeric")));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-parameter-type"
                && finding.message.contains("Optional")));
    }

    #[test]
    fn aligned_proc_versions_infer_parameter_from_all_defaults() {
        let make = |line: usize, default: i64| {
            serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
                "file":"code/test.dm","line":line,
                "parameters":[{"Name":"amount","type":null,"valueType":"anything",
                    "defaultValue":{"kind":"DMASTConstantInteger","fields":{"Value":default}}}],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}})
        };
        let input = format!("{}\n{}\n", make(1, 2), make(2, 3));
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(
            findings
                .iter()
                .filter(|finding| finding.rule == "unverified-inferred-parameter"
                    && finding.message.contains("amount is inferred as num"))
                .count(),
            2
        );
    }

    #[test]
    fn conflicting_call_and_default_do_not_infer_parameter() {
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":1,
            "parameters":[{"Name":"amount","type":null,"valueType":"anything",
                "defaultValue":{"kind":"DMASTConstantString","fields":{"Value":"text"}}}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Caller",
            "file":"code/test.dm","line":2,"parameters":[],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementExpression","fields":{"Expression":
                    {"kind":"DMASTProcCall","fields":{"Callable":
                        {"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"Run"}},
                        "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                            "Value":{"kind":"DMASTConstantInteger","fields":{"Value":2}}}}]}}}}]}}});
        let input = format!("{target}\n{caller}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-parameter-type"
                && finding.message.contains("amount")));
    }

    #[test]
    fn generated_admin_wrapper_forwards_implementation_parameter_type() {
        let wrapper_body = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementVarDeclaration","fields":{"Name":"_verb_args",
                "Type":"/list","Value":{"kind":"DMASTList","fields":{"Values":[
                    {"kind":"DMASTCallParameter","fields":{"Value":{"kind":"DMASTIdentifier",
                        "fields":{"Identifier":"usr"}},"Key":null}},
                    {"kind":"DMASTCallParameter","fields":{"Value":{"kind":"DMASTConstantPath",
                        "fields":{"Value":{"kind":"DMASTPath","fields":{
                            "Path":"/datum/admin_verb/example"}}}},"Key":null}}
                ],"IsAList":false}}}},
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTAppend","fields":{"LHS":{"kind":"DMASTIdentifier",
                    "fields":{"Identifier":"_verb_args"}},"RHS":{"kind":"DMASTIdentifier",
                    "fields":{"Identifier":"args"}}}}}},
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTDereference","fields":{"Expression":{"kind":"DMASTIdentifier",
                    "fields":{"Identifier":"SSadmin_verbs"}},"Operations":[{"kind":"CallOperation",
                    "fields":{"Identifier":"dynamic_invoke_verb","Parameters":[{
                        "kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                            "kind":"DMASTProcCall","fields":{"Callable":{
                                "kind":"DMASTCallableProcIdentifier","fields":{
                                    "Identifier":"arglist"}},"Parameters":[{
                                "kind":"DMASTCallParameter","fields":{"Key":null,
                                    "Value":{"kind":"DMASTIdentifier","fields":{
                                        "Identifier":"_verb_args"}}}}]}}}}]}}]}}}}
        ]}});
        let wrapper = serde_json::json!({"kind":"proc","owner":"/client","name":"__avd_example",
            "file":"code/admin.dm","line":10,"parameters":[{"Name":"value","type":null,
                "valueType":"anything","defaultValue":null}],"body":wrapper_body});
        let implementation = serde_json::json!({"kind":"proc",
            "owner":"/datum/admin_verb/example","name":"__avd_do_verb",
            "file":"code/admin.dm","line":10,"parameters":[
                {"Name":"user","type":"/client","valueType":null,"defaultValue":null},
                {"Name":"value","type":"/num","valueType":"num","defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let base = serde_json::json!({"kind":"proc","owner":"/datum/admin_verb",
            "name":"__avd_do_verb","file":"code/__defines/admin_verb.dm","line":58,
            "parameters":[],"body":{"kind":"DMASTProcBlockInner",
                "fields":{"Statements":[]}}});
        let input = format!("{base}\n{wrapper}\n{implementation}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding
                    .message
                    .contains("/client/__avd_example: value is inferred as num")));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unresolved-argument-pack"
                && finding.path == "code/admin.dm"));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "override-contract"
                && finding
                    .message
                    .contains("/datum/admin_verb/example/__avd_do_verb adds required")));
    }

    #[test]
    fn call_invalidates_src_liveness_before_return() {
        let contracts = crate::contracts::collect(
            "// dm-health: returns /datum/test\n/datum/test/proc/MaybeDeleted()\n",
        );
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"MaybeDeleted",
        "file":"code/test.dm","line":1,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementExpression","file":"code/test.dm","line":2,
                 "fields":{"Expression":{"kind":"DMASTProcCall","file":"code/test.dm",
                 "line":2,"fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                 "fields":{"Identifier":"UnknownEffect"}},"Parameters":[]}}}},
                {"kind":"DMASTProcStatementReturn","file":"code/test.dm","line":3,
                 "fields":{"Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}}}}
            ]}}});
        let input = proc.to_string();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &contracts,
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|f| f.rule == "strict-type-assignment" && f.message.contains("return")));
    }

    #[test]
    fn empty_super_call_forwards_current_arguments() {
        let base = serde_json::json!({"kind":"proc","owner":"/datum/base","name":"Run",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"amount","type":"/num",
            "valueType":"num","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[]}}});
        let child = serde_json::json!({"kind":"proc","owner":"/datum/base/child","name":"Run",
            "file":"code/test.dm","line":3,"parameters":[{"Name":"amount","type":"/num",
            "valueType":"num","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","file":"code/test.dm",
            "line":4,"fields":{"Expression":{"kind":"DMASTProcCall","file":"code/test.dm",
            "line":4,"fields":{"Callable":{"kind":"DMASTCallableSuper"},"Parameters":[]}}}}]}}});
        let input = format!("{}\n{}\n", base, child);
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings
            .iter()
            .any(|f| f.rule == "strict-type-assignment" && f.message.contains("omitted argument")));
    }

    #[test]
    fn empty_super_call_propagates_inferred_parameter_by_position() {
        let base = serde_json::json!({"kind":"proc","owner":"/datum/base","name":"Run",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"value","type":null,
            "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[]}}});
        let child = serde_json::json!({"kind":"proc","owner":"/datum/base/child","name":"Run",
            "file":"code/test.dm","line":2,"parameters":[{"Name":"renamed","type":"/num",
            "valueType":"num","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTProcCall","fields":{"Callable":{"kind":"DMASTCallableSuper"},
                "Parameters":[]}}}}]}}});
        let input = format!("{base}\n{child}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding
                    .message
                    .contains("/datum/base/Run: value is inferred as num")));
    }

    #[test]
    fn resolved_dynamic_call_contributes_parameter_evidence() {
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Accept",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"value","type":null,
            "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
            "kind":"DMASTCall","fields":{
                "CallParameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                    "Value":{"kind":"DMASTConstantPath","fields":{"Value":{
                        "kind":"DMASTPath","fields":{"Path":"/datum/test/proc/Accept"}}
                    }}}}],
                "ProcParameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,
                    "Value":{"kind":"DMASTConstantInteger","fields":{"Value":4}}}}]
            }
        }}}]}}});
        let input = format!("{target}\n{caller}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding.message.contains("Accept: value is inferred as num")));
    }

    #[test]
    fn untyped_parameter_reports_callsite_evidence() {
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Accept",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"value","type":null,
            "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[]}}});
        let relay = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Relay",
            "file":"code/test.dm","line":2,"parameters":[{"Name":"value","type":null,
            "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTProcCall","fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                "fields":{"Identifier":"Accept"}},"Parameters":[{"kind":"DMASTCallParameter",
                "fields":{"Key":null,"Value":{"kind":"DMASTIdentifier",
                "fields":{"Identifier":"value"}}}}]}}}}]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":3,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementVarDeclaration",
            "file":"code/test.dm","line":3,"fields":{"Name":"local","Type":null,
            "ValueType":"anything","Value":{"kind":"DMASTConstantInteger",
            "fields":{"Value":3}}}},
            {"kind":"DMASTProcStatementExpression","file":"code/test.dm",
            "line":4,"fields":{"Expression":{"kind":"DMASTProcCall","file":"code/test.dm",
            "line":4,"fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
            "fields":{"Identifier":"Relay"}},"Parameters":[{"kind":"DMASTCallParameter",
            "fields":{"Key":null,"Value":{"kind":"DMASTIdentifier",
            "fields":{"Identifier":"local"}}}}]}}}}]}}});
        let input = format!("{}\n{}\n{}\n", target, relay, caller);
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|f| f.rule == "unverified-inferred-parameter"
                && f.message.contains("Accept: value is inferred as num")));
        assert!(findings
            .iter()
            .any(|f| f.rule == "unverified-inferred-parameter"
                && f.message.contains("Relay: value is inferred as num")));
    }

    #[test]
    fn unresolved_call_argument_does_not_erase_precise_parameter_evidence() {
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Accept",
            "file":"code/test.dm","line":1,"parameters":[{"Name":"value","type":null,
                "valueType":"anything","defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let call = |line: usize, value: Value| {
            serde_json::json!({
            "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":line,
            "fields":{"Expression":{"kind":"DMASTProcCall","file":"code/test.dm",
                "line":line,"fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                    "fields":{"Identifier":"Accept"}},"Parameters":[{
                    "kind":"DMASTCallParameter","file":"code/test.dm","line":line,
                    "fields":{"Key":null,"Value":value}}]}}}})
        };
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":3,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            call(4, serde_json::json!({"kind":"DMASTConstantInteger",
                "fields":{"Value":3}})),
            call(5, serde_json::json!({"kind":"DMASTIdentifier",
                "fields":{"Identifier":"mystery"}}))
        ]}}});
        let input = format!("{target}\n{caller}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding.message.contains("Accept: value is inferred as num")));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unknown-type-flow"
                && finding.message.contains("argument value")));
    }

    #[test]
    fn numeric_parameter_use_infers_storage_without_call_sites() {
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Compute",
        "file":"code/test.dm","line":1,"parameters":[{"Name":"amount","type":null,
        "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementReturn","fields":{"Value":{
            "kind":"DMASTMultiply","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"amount"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":2}}
            }}}}]}}});
        let input = format!("{proc}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding
                    .message
                    .contains("Compute: amount is inferred as num from 1 numeric uses")));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "unknown-parameter-type"
                && finding.message.contains("amount")));
    }

    #[test]
    fn inferred_parameter_propagates_into_field_write() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"total",
            "file":"code/test.dm","line":1,"type":null,"valueType":"anything",
            "initializer":null});
        let setter = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Set",
        "file":"code/test.dm","line":2,"parameters":[{"Name":"value","type":null,
        "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
            "kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"total"}},
                "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}}
            }}}}]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":3,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTProcCall","fields":{"Callable":{"kind":"DMASTCallableProcIdentifier",
                "fields":{"Identifier":"Set"}},"Parameters":[{"kind":"DMASTCallParameter",
                "fields":{"Key":null,"Value":{"kind":"DMASTConstantInteger",
                "fields":{"Value":3}}}}]}}}}]}}});
        let input = format!("{field}\n{setter}\n{caller}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(!findings.iter().any(
            |finding| finding.rule == "unknown-field-type" && finding.message.contains("total")
        ));
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding.message.contains("Set: value is inferred as num")));
    }

    #[test]
    fn constructor_arguments_infer_new_parameter_and_field() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"total",
            "file":"code/test.dm","line":1,"type":null,"valueType":"anything",
            "initializer":null});
        let constructor = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"New",
        "file":"code/test.dm","line":2,"parameters":[{"Name":"value","type":null,
        "valueType":"anything","defaultValue":null}],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
            "kind":"DMASTAssign","fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"total"}},
                "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"value"}}
            }}}}]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
            "file":"code/test.dm","line":3,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTNewPath","fields":{"Path":{"kind":"DMASTConstantPath",
                "fields":{"Value":{"kind":"DMASTPath","fields":{"Path":"/datum/test"}}}},"Parameters":[{"kind":"DMASTCallParameter",
                "fields":{"Key":null,"Value":{"kind":"DMASTConstantInteger",
                "fields":{"Value":3}}}}]}}}}]}}});
        let inferred_caller = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"RunInferred","file":"code/test.dm","line":4,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{
            "kind":"DMASTProcStatementVarDeclaration","fields":{
                "Name":"made","Type":"/datum/test","ValueType":null,
                "Value":{"kind":"DMASTNewInferred","fields":{"Parameters":[{
                    "kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                        "kind":"DMASTConstantInteger","fields":{"Value":4}}
                    }}]}}
            }
        }]}}});
        let input = format!("{field}\n{constructor}\n{caller}\n{inferred_caller}\n");
        let (findings, coverage) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unverified-inferred-parameter"
                && finding
                    .message
                    .contains("New: value is inferred as num from 2 static calls")));
        assert!(!findings.iter().any(
            |finding| finding.rule == "unknown-field-type" && finding.message.contains("total")
        ));
        assert_eq!(coverage.unresolved_by_kind.get("DMASTNewInferred"), None);
    }

    #[test]
    fn inferred_new_uses_direct_field_destination_type() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"made",
            "file":"code/test.dm","line":1,"type":"/datum/test","valueType":"anything",
            "initializer":null});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Make",
            "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
            "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","file":"code/test.dm",
                "line":3,"fields":{"Expression":{"kind":"DMASTAssign","file":"code/test.dm",
                "line":3,"fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"made"}},
                    "RHS":{"kind":"DMASTNewInferred","file":"code/test.dm","line":3,
                        "fields":{"Parameters":[]}}}}}}]}}});
        let input = format!("{field}\n{proc}\n");
        let symbols = Symbols::collect(input.as_bytes(), &[]).unwrap();
        let (findings, coverage) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert_eq!(coverage.unresolved_by_kind.get("DMASTNewInferred"), None);
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment" && finding.line == 3));
    }

    #[test]
    fn resource_literals_have_file_icon_or_sound_types() {
        let symbols = Symbols::default();
        let selection = Selection::default();
        let checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let literal = |path| {
            serde_json::json!({"kind":"DMASTConstantResource",
            "fields":{"Path":path}})
        };
        assert_eq!(
            checker.expression(&literal("icons/test.dmi"), &HashMap::new(), "/"),
            Ty::parse("icon")
        );
        assert_eq!(
            checker.expression(&literal("sound/test.ogg"), &HashMap::new(), "/"),
            Ty::parse("sound")
        );
        assert_eq!(
            checker.expression(&literal("data/test.json"), &HashMap::new(), "/"),
            Ty::parse("file")
        );
        assert!(Ty::parse("file").accepts(&Ty::parse("icon"), &symbols));
        assert!(!Ty::parse("sound").accepts(&Ty::parse("icon"), &symbols));
        assert_eq!(
            Ty::parse("icon").join(&Ty::parse("sound"), &symbols),
            Ty::parse("file")
        );
        let step = serde_json::json!({"kind":"DMASTGetStep","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
        }});
        assert_eq!(
            checker.expression(&step, &HashMap::new(), "/datum/test"),
            Ty::parse("/turf?")
        );
    }

    #[test]
    fn modified_new_override_checks_field_value() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/test","name":"count",
            "file":"code/test.dm","line":1,"type":"/num","valueType":"num",
            "initializer":{"kind":"DMASTConstantInteger","fields":{"Value":0}}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test","name":"Run",
        "file":"code/test.dm","line":2,"parameters":[],"body":{"kind":"DMASTProcBlockInner",
        "fields":{"Statements":[{"kind":"DMASTProcStatementExpression","fields":{"Expression":{
            "kind":"DMASTNewModifiedType","file":"code/test.dm","line":3,"fields":{
                "Type":{"kind":"DMASTModifiedType","fields":{
                    "Value":{"kind":"DMASTPath","fields":{"Path":"/datum/test"}},
                    "VarOverridesAst":[{"name":"count","value":{
                        "kind":"DMASTConstantString","file":"code/test.dm","line":3,
                        "fields":{"Value":"wrong"}}}]
                }},"Parameters":[]
            }
        }}}]}}});
        let input = format!("{field}\n{proc}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("/datum/test.count")));
    }

    #[test]
    fn computed_argument_key_does_not_bind_as_positional() {
        let target = serde_json::json!({"kind":"proc","owner":"/datum/test",
            "name":"Accept","file":"code/test.dm","line":1,
            "parameters":[{"Name":"amount","type":"/num","valueType":"num",
                "defaultValue":null}],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let caller = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Run","file":"code/test.dm","line":3,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementExpression","file":"code/test.dm",
             "line":4,"fields":{"Expression":{"kind":"DMASTProcCall",
             "file":"code/test.dm","line":4,"fields":{
                "Callable":{"kind":"DMASTCallableProcIdentifier",
                    "fields":{"Identifier":"Accept"}},
                "Parameters":[{"kind":"DMASTCallParameter","file":"code/test.dm",
                    "line":4,"fields":{
                        "Key":{"kind":"DMASTIdentifier",
                            "fields":{"Identifier":"runtime_key"}},
                        "Value":{"kind":"DMASTConstantString",
                            "fields":{"Value":"not a number"}}
                    }}]
             }}}}
        ]}}});
        let input = format!("{target}\n{caller}\n");
        let (findings, _) = analyze(
            input.as_bytes(),
            input.as_bytes(),
            input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "unresolved-argument-key"));
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "strict-type-assignment"
                && finding.message.contains("argument amount")));

        let mut untyped = target;
        untyped["parameters"][0]["type"] = Value::Null;
        untyped["parameters"][0]["valueType"] = Value::String("anything".into());
        let untyped_input = format!("{untyped}\n{caller}\n");
        let (untyped_findings, _) = analyze(
            untyped_input.as_bytes(),
            untyped_input.as_bytes(),
            untyped_input.as_bytes(),
            &Symbols::default(),
            &[],
            &Selection {
                all: true,
                ..Selection::default()
            },
        )
        .unwrap();
        assert!(untyped_findings
            .iter()
            .any(|finding| finding.rule == "unknown-parameter-type"
                && finding.message.contains("1 unresolved")));
    }

    #[test]
    fn strict_field_rejects_null_start_and_wrong_subtree() {
        let field = serde_json::json!({"kind":"field","owner":"/datum/holder","name":"item",
            "file":"code/test.dm","line":1,"type":"/obj/item","valueType":"anything","initializer":null});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/holder","name":"SetItem",
        "file":"code/test.dm","line":3,"parameters":[],"body":{
            "kind":"DMASTProcBlockInner","fields":{"Statements":[{
                "kind":"DMASTProcStatementExpression","file":"code/test.dm","line":4,"fields":{"Expression":{
                    "kind":"DMASTAssign","file":"code/test.dm","line":4,"fields":{
                        "LHS":{"kind":"DMASTDereference","fields":{
                            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
                            "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"item","Safe":false}}]
                        }},
                        "RHS":{"kind":"DMASTNewPath","fields":{"Path":{"kind":"DMASTConstantPath","fields":{
                            "Value":{"kind":"DMASTPath","fields":{"Path":"/mob"}}
                        }}}}
                    }
                }}
            }]}
        }});
        let ast = format!("{field}\n{proc}\n");
        let symbols = Symbols::collect(ast.as_bytes(), &[]).unwrap();
        let (findings, _) = analyze(
            ast.as_bytes(),
            ast.as_bytes(),
            ast.as_bytes(),
            &symbols,
            &[],
            &Selection {
                all: true,
                modules: vec![],
                files: None,
            },
        )
        .unwrap();
        assert!(findings
            .iter()
            .any(|f| f.rule == "required-field-uninitialized"));
        assert!(findings.iter().any(|f| f.rule == "strict-type-assignment"));
    }
    #[test]
    fn loop_effects_do_not_prove_mutable_field_writes() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let key = ("/datum/test".into(), "items".into());
        checker.fields.insert(
            key.clone(),
            FieldInfo {
                ty: Ty::parse("list<num>"),
                explicit_type: true,
                evidence: Ty::Null,
                origin: serde_json::json!({"kind":"field"}),
                nullable: false,
                delayed: false,
                phase: None,
                proved_initialization: false,
                initially_null: false,
                saw_unknown_write: false,
                conflict: false,
            },
        );
        let loop_node = serde_json::json!({"kind":"DMASTProcStatementWhile","fields":{
            "Conditional":{"kind":"DMASTProcCall","fields":{
                "Callable":{"kind":"DMASTCallable","fields":{"Identifier":"unknown_proc"}}
            }},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                    "kind":"DMASTAssign","fields":{
                        "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
                        "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"values"}}
                    }
                }}}
            ]}}
        }});
        let vars = HashMap::from([("values".into(), Ty::parse("list<num>"))]);
        checker.register_writes(&loop_node, "/datum/test", &vars, &HashSet::new());
        assert!(checker.fields[&key].saw_unknown_write);
        checker.fields.get_mut(&key).unwrap().saw_unknown_write = false;
        let block = serde_json::json!({"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTProcCall","fields":{
                    "Callable":{"kind":"DMASTCallable","fields":{"Identifier":"unknown_proc"}}
                }
            }}},
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTAssign","fields":{
                    "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
                    "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"values"}}
                }
            }}}
        ]}});
        checker.register_writes(&block, "/datum/test", &vars, &HashSet::new());
        assert!(checker.fields[&key].saw_unknown_write);
    }

    #[test]
    fn pick_initial_and_locate_preserve_static_result_types() {
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        let pick = serde_json::json!({"kind":"DMASTPick","fields":{"Values":[
            {"kind":"PickValue","fields":{"Weight":null,"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":1}}}},
            {"kind":"PickValue","fields":{"Weight":{"kind":"DMASTConstantInteger",
                "fields":{"Value":10}},"Value":{
                "kind":"DMASTConstantNull","fields":{}}}}
        ]}});
        assert_eq!(
            checker.expression(&pick, &HashMap::new(), "/datum/test"),
            Ty::parse("num?")
        );
        let locate = serde_json::json!({"kind":"DMASTLocate","fields":{
            "Expression":{"kind":"DMASTConstantPath","fields":{
                "Value":{"kind":"DMASTPath","fields":{"Path":"/obj/item"}}}},
            "Container":null}});
        assert_eq!(
            checker.expression(&locate, &HashMap::new(), "/datum/test"),
            Ty::parse("/obj/item?")
        );
        let coords = serde_json::json!({"kind":"DMASTLocateCoordinates","fields":{
            "X":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "Y":{"kind":"DMASTConstantInteger","fields":{"Value":2}},
            "Z":{"kind":"DMASTConstantInteger","fields":{"Value":3}}}});
        assert_eq!(
            checker.expression(&coords, &HashMap::new(), "/datum/test"),
            Ty::parse("/turf?")
        );
        checker.register(&serde_json::json!({"kind":"field","owner":"/datum/test",
            "name":"count","type":"/num","valueType":"num",
            "initializer":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}));
        let initial = serde_json::json!({"kind":"DMASTInitial","fields":{
            "Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"count"}}}});
        assert_eq!(
            checker.expression(&initial, &HashMap::new(), "/datum/test"),
            Ty::Num
        );
        let local = HashMap::from([("count".into(), Ty::Text)]);
        assert_eq!(
            checker.expression(&initial, &local, "/datum/test"),
            Ty::Unknown
        );
        let append = serde_json::json!({"kind":"DMASTAppend","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "RHS":{"kind":"DMASTConstantString","fields":{"Value":"new"}}}});
        let items = HashMap::from([("items".into(), Ty::parse("list<num>"))]);
        assert_eq!(
            checker.expression(&append, &items, "/datum/test"),
            Ty::List(Box::new(Ty::Unknown))
        );
        let subtract = serde_json::json!({"kind":"DMASTSubtract","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        assert_eq!(
            checker.expression(&subtract, &items, "/datum/test"),
            Ty::parse("list<num>")
        );
        let or = serde_json::json!({"kind":"DMASTOr","fields":{
            "LHS":{"kind":"DMASTConstantNull","fields":{}},
            "RHS":{"kind":"DMASTConstantString","fields":{"Value":"fallback"}}}});
        assert_eq!(
            checker.expression(&or, &HashMap::new(), "/datum/test"),
            Ty::Text
        );
        let mixed = serde_json::json!({"kind":"DMASTList","fields":{"Values":[
            {"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":1}}}},
            {"kind":"DMASTCallParameter","fields":{"Key":{
                "kind":"DMASTConstantString","fields":{"Value":"answer"}},"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":42}}}}
        ]}});
        assert_eq!(
            checker.expression(&mixed, &HashMap::new(), "/datum/test"),
            Ty::parse("list<num>")
        );
        let remove = serde_json::json!({"kind":"DMASTRemove","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        assert_eq!(
            checker.expression(&remove, &items, "/datum/test"),
            Ty::parse("list<num>")
        );
        let combine = serde_json::json!({"kind":"DMASTCombine","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":2}}}});
        assert_eq!(
            checker.expression(&combine, &items, "/datum/test"),
            Ty::parse("list<num>")
        );
        let add_nullable_num = serde_json::json!({"kind":"DMASTAdd","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"maybe"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        let optional = HashMap::from([("maybe".into(), Ty::parse("num?"))]);
        assert_eq!(
            checker.expression(&add_nullable_num, &optional, "/datum/test"),
            Ty::Num
        );
        let inherited_field = |member| {
            serde_json::json!({"kind":"DMASTDereference","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"thing"}},
            "Operations":[{"kind":"FieldOperation","fields":{
                "Identifier":member,"Safe":false}}]}})
        };
        let thing = HashMap::from([("thing".into(), Ty::parse("/obj/item"))]);
        assert_eq!(
            checker.expression(&inherited_field("dir"), &thing, "/datum/test"),
            Ty::Num
        );
        assert_eq!(
            checker.expression(&inherited_field("name"), &thing, "/datum/test"),
            Ty::parse("text?")
        );
        let env = Env {
            facts: thing,
            ..Env::default()
        };
        checker.inspect_expr(&inherited_field("dir"), "/datum/test", &env);
        assert!(!checker.findings.iter().any(|finding| {
            finding.rule == "unresolved-member-read" || finding.rule == "strict-null-dereference"
        }));
    }

    #[test]
    fn fixed_result_builtins_and_nullable_numeric_operators() {
        assert_eq!(dimensional_list_type(2), Ty::parse("list<list<unknown>>"));
        assert_eq!(dimensional_list_type(0), Ty::EmptyList);
        let empty_new = serde_json::json!({"kind":"DMASTNewInferred","fields":{"Parameters":[]}});
        assert_eq!(
            contextual_new_type(&empty_new, &Ty::parse("/datum/test?")),
            Some(Ty::parse("/datum/test"))
        );
        assert_eq!(
            contextual_new_type(&empty_new, &Ty::parse("list<num>")),
            Some(Ty::EmptyList)
        );
        assert_eq!(
            contextual_new_type(&empty_new, &Ty::parse("alist<text,num>")),
            Some(Ty::EmptyAlist)
        );
        let bare_new = serde_json::json!({"kind":"DMASTNewInferred","fields":{"Parameters":null}});
        assert_eq!(
            contextual_new_type(&bare_new, &Ty::parse("list<num>")),
            Some(Ty::EmptyList)
        );
        let sized_new = serde_json::json!({"kind":"DMASTNewInferred","fields":{"Parameters":[
            {"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                "kind":"DMASTConstantInteger","fields":{"Value":5}}}}
        ]}});
        assert_eq!(
            contextual_new_type(&sized_new, &Ty::parse("list<num>")),
            None
        );
        assert_eq!(contextual_new_type(&empty_new, &Ty::Unknown), None);
        for syntax_node in [
            "DMASTVarDeclExpression",
            "DMASTSwitchCaseRange",
            "DMASTCallableSelf",
        ] {
            assert!(!is_value_expression(syntax_node));
        }
        assert!(is_value_expression("DMASTBinaryAnd"));
        let symbols = Symbols::default();
        let selection = Selection {
            all: true,
            ..Selection::default()
        };
        let mut checker = Checker {
            symbols: &symbols,
            contracts: &[],
            selection: &selection,
            fields: HashMap::new(),
            overrides: Vec::new(),
            procs: HashMap::new(),
            proc_versions: HashMap::new(),
            checked_versions: HashMap::new(),
            param_evidence: HashMap::new(),
            return_bodies: HashMap::new(),
            new_bodies: HashMap::new(),
            current_proc: None,
            current_proc_version: None,
            inferred_locals: HashMap::new(),
            findings: Vec::new(),
            coverage: TypeCoverage::default(),
        };
        checker.procs.insert(
            ("/datum/test".into(), "Run".into()),
            Signature {
                parameters: Vec::new(),
                result: Ty::Void,
                result_required: false,
                inferred_nullable_result: false,
                path: "code/test.dm".into(),
                line: 1,
            },
        );
        let upward = serde_json::json!({"kind":"DMASTUpwardPathSearch","fields":{
            "Path":{"kind":"DMASTConstantPath","fields":{"Value":{"kind":"DMASTPath","fields":{"Path":"/datum/test/child"}}}},
            "Search":{"kind":"DMASTPath","fields":{"Path":"proc/Run"}}
        }});
        assert_eq!(
            checker.expression(&upward, &HashMap::new(), "/datum/test"),
            Ty::TypePath("/datum/test/proc/Run".into())
        );
        let sizes = serde_json::json!({"kind":"DMASTDimensionalList","fields":{"Sizes":[
            {"kind":"DMASTConstantInteger","fields":{"Value":10}},
            {"kind":"DMASTConstantInteger","fields":{"Value":5}}
        ]}});
        assert_eq!(
            checker.expression(&sizes, &HashMap::new(), "/datum/test"),
            Ty::parse("list<list<unknown>>")
        );
        let allocated = serde_json::json!({"kind":"DMASTNewPath","fields":{
            "Path":{"kind":"DMASTConstantPath","fields":{"Value":{"kind":"DMASTPath","fields":{"Path":"/list"}}}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{"kind":"DMASTConstantInteger","fields":{"Value":10}}}},
                {"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{"kind":"DMASTConstantInteger","fields":{"Value":5}}}}]
        }});
        assert_eq!(
            checker.expression(&allocated, &HashMap::new(), "/datum/test"),
            Ty::parse("list<list<unknown>>")
        );
        let dynamic_list = serde_json::json!({"kind":"DMASTNewExpr","fields":{
            "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"kind"}},
            "Parameters":[]
        }});
        let list_path = HashMap::from([("kind".into(), Ty::TypePath("/list".into()))]);
        assert_eq!(
            checker.expression(&dynamic_list, &list_path, "/datum/test"),
            Ty::EmptyList
        );
        let unknown = serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"x"}});
        let ascii = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"text2ascii"}},
            "Parameters":[{"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{
                "kind":"DMASTConstantString","fields":{"Value":"A"}}}}]
        }});
        assert_eq!(
            checker.expression(&ascii, &HashMap::new(), "/datum/test"),
            Ty::Num
        );
        let codepoint_offset = serde_json::json!({"kind":"DMASTSubtract","fields":{
            "LHS":ascii,"RHS":{"kind":"DMASTConstantInteger","fields":{"Value":55}}}});
        assert_eq!(
            checker.expression(&codepoint_offset, &HashMap::new(), "/datum/test"),
            Ty::Num
        );
        let max_vectors = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"max"}},
            "Parameters":[
                {"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"left"}}}},
                {"kind":"DMASTCallParameter","fields":{"Key":null,"Value":{"kind":"DMASTIdentifier","fields":{"Identifier":"right"}}}}
            ]
        }});
        let vectors = HashMap::from([
            ("left".into(), Ty::Path("/vector".into())),
            ("right".into(), Ty::Path("/vector".into())),
        ]);
        assert_eq!(
            checker.expression(&max_vectors, &vectors, "/datum/test"),
            Ty::Path("/vector".into())
        );
        for name in [
            "DMASTGetDir",
            "DMASTAbs",
            "DMASTLog",
            "DMASTSqrt",
            "DMASTSin",
            "DMASTCos",
            "DMASTArctan",
            "DMASTArctan2",
            "DMASTExpressionInRange",
        ] {
            let node = serde_json::json!({"kind":name,"fields":{"Value":unknown}});
            assert_eq!(
                checker.expression(&node, &HashMap::new(), "/datum/test"),
                Ty::Num,
                "{name}"
            );
        }
        let rgb = serde_json::json!({"kind":"DMASTRgb","fields":{"R":unknown}});
        assert_eq!(
            checker.expression(&rgb, &HashMap::new(), "/datum/test"),
            Ty::Text
        );
        let addtext = serde_json::json!({"kind":"DMASTAddText","fields":{"Parameters":[]}});
        assert_eq!(
            checker.expression(&addtext, &HashMap::new(), "/datum/test"),
            Ty::Text
        );
        let multiply = serde_json::json!({"kind":"DMASTMultiply","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"maybe"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":2}}
        }});
        let vars = HashMap::from([("maybe".into(), Ty::parse("num?"))]);
        assert_eq!(checker.expression(&multiply, &vars, "/datum/test"), Ty::Num);
        let flags = serde_json::json!({"kind":"DMASTBinaryAnd","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"maybe"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":4}}
        }});
        assert_eq!(checker.expression(&flags, &vars, "/datum/test"), Ty::Num);
        let unknown_flag =
            serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"dynamic_result"}});
        for operator in [
            "DMASTBinaryOr",
            "DMASTBinaryAnd",
            "DMASTBinaryXor",
            "DMASTCombine",
            "DMASTMask",
        ] {
            let bitwise = serde_json::json!({"kind":operator,"file":"code/test.dm","line":4,
                "fields":{"LHS":{"kind":"DMASTConstantInteger","fields":{"Value":0}},
                    "RHS":unknown_flag}});
            assert_eq!(
                checker.expression(&bitwise, &HashMap::new(), "/datum/test"),
                Ty::Num
            );
            checker.inspect_expr(&bitwise, "/datum/test", &Env::default());
        }
        assert_eq!(checker.coverage.unresolved_assignments, 5);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unknown-type-flow"
                && finding.message.contains("bitwise right operand")));
        for operator in ["DMASTBinaryAnd", "DMASTMask"] {
            let intersection = serde_json::json!({"kind":operator,"fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
                "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"dynamic_result"}}
            }});
            assert_eq!(
                checker.expression(
                    &intersection,
                    &HashMap::from([("items".into(), Ty::parse("list<text>"))]),
                    "/datum/test"
                ),
                Ty::parse("list<text>")
            );
        }
        let zero = HashMap::from([("maybe".into(), Ty::Null)]);
        assert_eq!(checker.expression(&flags, &zero, "/datum/test"), Ty::Num);
        for operator in ["DMASTAppend", "DMASTRemove", "DMASTCombine"] {
            let update = serde_json::json!({"kind":operator,"fields":{
                "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"maybe"}},
                "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
            }});
            assert_eq!(
                checker.expression(&update, &vars, "/datum/test"),
                Ty::Num,
                "{operator}"
            );
        }
        let bad = HashMap::from([("maybe".into(), Ty::Text)]);
        assert_eq!(
            checker.expression(&multiply, &bad, "/datum/test"),
            Ty::Unknown
        );
        assert_eq!(checker.expression(&flags, &bad, "/datum/test"), Ty::Unknown);
        let and = serde_json::json!({"kind":"DMASTAnd","fields":{
            "LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"object"}},
            "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
        }});
        let nullable_object = HashMap::from([("object".into(), Ty::parse("/datum/test?"))]);
        assert_eq!(
            checker.expression(&and, &nullable_object, "/datum/test"),
            Ty::parse("num?")
        );
        let object = HashMap::from([("object".into(), Ty::parse("/datum/test"))]);
        assert_eq!(checker.expression(&and, &object, "/datum/test"), Ty::Num);
        let mut or = and.clone();
        or["kind"] = Value::String("DMASTOr".into());
        assert_eq!(
            checker.expression(&or, &object, "/datum/test"),
            Ty::parse("/datum/test")
        );
        let null_object = HashMap::from([("object".into(), Ty::Null)]);
        assert_eq!(
            checker.expression(&or, &null_object, "/datum/test"),
            Ty::Num
        );
        let length = serde_json::json!({"kind":"DMASTDereference","file":"code/test.dm","line":5,
            "fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"items"}},
            "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"len","Safe":false}}]}});
        let collections = HashMap::from([("items".into(), Ty::parse("list<num>?"))]);
        assert_eq!(
            checker.expression(&length, &collections, "/datum/test"),
            Ty::Num
        );
        let env = Env {
            facts: collections,
            ..Env::default()
        };
        checker.inspect_expr(&length, "/datum/test", &env);
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.rule == "strict-null-dereference"));
        assert!(!checker
            .findings
            .iter()
            .any(|finding| finding.rule == "unresolved-member-read"));
        let locate = serde_json::json!({"kind":"DMASTLocateCoordinates","file":"code/test.dm","line":6,
            "fields":{"X":{"kind":"DMASTIdentifier","fields":{"Identifier":"unknown_x"}},
            "Y":{"kind":"DMASTConstantInteger","fields":{"Value":2}},
            "Z":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}});
        assert_eq!(
            checker.expression(&locate, &HashMap::new(), "/datum/test"),
            Ty::parse("/turf?")
        );
        checker.inspect_expr(&locate, "/datum/test", &Env::default());
        assert!(checker
            .findings
            .iter()
            .any(|finding| finding.message.contains("locate X coordinate")));
        checker.coverage = TypeCoverage::default();
        let condition = serde_json::json!({"kind":"DMASTAnd","file":"code/test.dm","line":7,
            "fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"flag"}},
            "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"object"}}}});
        let env = Env {
            facts: HashMap::from([
                ("flag".into(), Ty::Num),
                ("object".into(), Ty::Path("/datum/test".into())),
            ]),
            ..Env::default()
        };
        checker.inspect_condition(&condition, "/datum/test", &env);
        assert_eq!(checker.coverage.unresolved_expressions, 1);
        assert_eq!(
            checker
                .coverage
                .unresolved_causes
                .get("Condition-only logical value"),
            Some(&1)
        );
        assert!(checker
            .coverage
            .unresolved_roots
            .values()
            .any(|root| { root.category == "Condition-only logical value" && root.line == 7 }));
        checker.coverage = TypeCoverage::default();
        checker.inspect_expr(&condition, "/datum/test", &env);
        assert_eq!(checker.coverage.unresolved_expressions, 1);
        assert_eq!(
            checker
                .coverage
                .unresolved_causes
                .get("Operator or unsupported expression"),
            Some(&1)
        );
    }
}
