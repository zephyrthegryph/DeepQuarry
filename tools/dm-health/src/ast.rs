//! Health and local type checks over OpenDream's parsed AST export.
use crate::contracts::{Contract, Visibility};
use crate::symbols::Symbols;
use crate::Finding;
use serde::Deserialize;
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::io::{self, BufRead};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Nullability {
    Null,
    NonNull,
    Maybe,
    Unknown,
}

#[derive(Clone, Debug)]
struct TypeState {
    kind: String,
    null: Nullability,
    alias_id: u64,
}

impl TypeState {
    fn unknown() -> Self {
        Self {
            kind: "unknown".into(),
            null: Nullability::Unknown,
            alias_id: 0,
        }
    }
}

fn field<'a>(node: &'a Value, key: &str) -> &'a Value {
    &node["fields"][key]
}
fn kind(node: &Value) -> &str {
    node["kind"].as_str().unwrap_or("")
}
fn unwrap_expression(mut node: &Value) -> &Value {
    while kind(node) == "DMASTExpressionWrapped" {
        node = field(node, "Value");
    }
    node
}
fn string(node: &Value) -> Option<&str> {
    node.as_str()
}
fn location(node: &Value, fallback: &str) -> (String, usize) {
    (
        node["file"].as_str().unwrap_or(fallback).replace('\\', "/"),
        node["line"].as_u64().unwrap_or(1) as usize,
    )
}
fn children(node: &Value) -> impl Iterator<Item = &Value> {
    node["fields"]
        .as_object()
        .into_iter()
        .flat_map(|fields| fields.values())
        .flat_map(|value| {
            if let Some(array) = value.as_array() {
                array.iter().collect::<Vec<_>>()
            } else {
                vec![value]
            }
        })
        .filter(|value| value.is_object() && value.get("kind").is_some())
}
fn calls_named(node: &Value, name: &str) -> bool {
    (kind(node) == "DMASTProcCall"
        && field(field(node, "Callable"), "Identifier").as_str() == Some(name))
        || children(node).any(|child| calls_named(child, name))
}
fn sleep_calls(node: &Value, path: &str, lines: &mut Vec<(String, usize)>) {
    if kind(node) == "DMASTProcCall"
        && field(field(node, "Callable"), "Identifier").as_str() == Some("sleep")
    {
        lines.push(location(node, path));
    }
    for child in children(node) {
        sleep_calls(child, path, lines);
    }
}
fn join(a: &Nullability, b: &Nullability) -> Nullability {
    if a == b {
        *a
    } else if *a == Nullability::Unknown || *b == Nullability::Unknown {
        Nullability::Unknown
    } else {
        Nullability::Maybe
    }
}
fn merge(
    a: &HashMap<String, TypeState>,
    b: &HashMap<String, TypeState>,
) -> HashMap<String, TypeState> {
    let mut result = a.clone();
    for (name, other) in b {
        result
            .entry(name.clone())
            .and_modify(|current| {
                current.null = join(&current.null, &other.null);
                if current.kind != other.kind {
                    current.kind = "unknown".into();
                }
                if current.alias_id != other.alias_id {
                    current.alias_id = 0;
                }
            })
            .or_insert_with(|| other.clone());
    }
    result
}
fn value(
    expr: &Value,
    vars: &HashMap<String, TypeState>,
    symbols: &Symbols,
    owner: &str,
) -> TypeState {
    match kind(expr) {
        "DMASTConstantNull" => TypeState {
            kind: "null".into(),
            null: Nullability::Null,
            alias_id: 0,
        },
        "DMASTConstantInteger" | "DMASTConstantFloat" => TypeState {
            kind: "num".into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTConstantString" => TypeState {
            kind: "text".into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTList" | "DMASTNewList" => TypeState {
            kind: "list".into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTNewPath" => TypeState {
            kind: field(field(field(expr, "Path"), "Value"), "Path")
                .as_str()
                .unwrap_or("unknown")
                .into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTNewModifiedType" => TypeState {
            kind: field(field(field(expr, "Type"), "Value"), "Path")
                .as_str()
                .unwrap_or("unknown")
                .into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTNewExpr" => TypeState {
            kind: "unknown".into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTNewInferred" => TypeState {
            kind: "unknown".into(),
            null: Nullability::NonNull,
            alias_id: 0,
        },
        "DMASTIdentifier" => {
            let name = field(expr, "Identifier").as_str().unwrap_or("");
            if name == "src" {
                TypeState {
                    kind: owner.into(),
                    null: Nullability::NonNull,
                    alias_id: 0,
                }
            } else {
                vars.get(name).cloned().unwrap_or_else(TypeState::unknown)
            }
        }
        "DMASTExpressionWrapped" => value(field(expr, "Value"), vars, symbols, owner),
        "DMASTProcCall" => {
            let callable = field(expr, "Callable");
            let name = field(callable, "Identifier").as_str().unwrap_or("");
            symbols
                .proc(owner, name)
                .map(|proc| TypeState {
                    kind: proc.return_kind.clone(),
                    null: if proc.return_nonnull {
                        Nullability::NonNull
                    } else {
                        Nullability::Unknown
                    },
                    alias_id: 0,
                })
                .unwrap_or_else(TypeState::unknown)
        }
        "DMASTDereference" => {
            let receiver = value(field(expr, "Expression"), vars, symbols, owner);
            let op = field(expr, "Operations")
                .as_array()
                .and_then(|ops| ops.first());
            let member = op
                .and_then(|op| field(op, "Identifier").as_str())
                .unwrap_or("");
            match op.map(kind) {
                Some("FieldOperation") => symbols
                    .field(&receiver.kind, member)
                    .map(|field| TypeState {
                        kind: field.kind.clone(),
                        null: if field.nonnull {
                            Nullability::NonNull
                        } else {
                            Nullability::Maybe
                        },
                        alias_id: 0,
                    })
                    .unwrap_or_else(TypeState::unknown),
                Some("CallOperation") => symbols
                    .proc(&receiver.kind, member)
                    .map(|proc| TypeState {
                        kind: proc.return_kind.clone(),
                        null: if proc.return_nonnull {
                            Nullability::NonNull
                        } else {
                            Nullability::Unknown
                        },
                        alias_id: 0,
                    })
                    .unwrap_or_else(TypeState::unknown),
                _ => TypeState::unknown(),
            }
        }
        _ => TypeState::unknown(),
    }
}
fn compatible(expected: &str, actual: &str) -> bool {
    expected == "unknown"
        || actual == "unknown"
        || actual == "null"
        || expected == actual
        || (expected == "/list" && actual == "list")
        || actual.starts_with(&format!("{expected}/"))
        || (expected == "/datum" && actual.starts_with('/'))
        || (expected == "/atom"
            && ["/obj", "/mob", "/turf", "/area"]
                .iter()
                .any(|root| actual == *root || actual.starts_with(&format!("{root}/"))))
        || (expected == "/atom/movable"
            && ["/obj", "/mob"]
                .iter()
                .any(|root| actual == *root || actual.starts_with(&format!("{root}/"))))
}
fn constant_zero(node: &Value) -> bool {
    matches!(kind(node), "DMASTConstantInteger" | "DMASTConstantFloat")
        && field(node, "Value").as_f64() == Some(0.0)
}
fn null_guard(node: &Value) -> Option<(&str, bool)> {
    let (candidate, null_on_true) = match kind(node) {
        "DMASTIdentifier" => (node, false),
        "DMASTNot" => (field(node, "Value"), true),
        "DMASTEqual" | "DMASTNotEqual" => {
            let lhs = field(node, "LHS");
            let rhs = field(node, "RHS");
            let candidate = if kind(lhs) == "DMASTConstantNull" {
                rhs
            } else if kind(rhs) == "DMASTConstantNull" {
                lhs
            } else {
                return None;
            };
            (candidate, kind(node) == "DMASTEqual")
        }
        _ => return None,
    };
    if kind(candidate) == "DMASTIdentifier" {
        Some((field(candidate, "Identifier").as_str()?, null_on_true))
    } else {
        None
    }
}

fn narrowed(
    condition: &Value,
    truth: bool,
    vars: &HashMap<String, TypeState>,
) -> HashMap<String, TypeState> {
    match kind(condition) {
        "DMASTNot" => narrowed(field(condition, "Value"), !truth, vars),
        "DMASTAnd" if truth => {
            let left = narrowed(field(condition, "LHS"), true, vars);
            narrowed(field(condition, "RHS"), true, &left)
        }
        "DMASTAnd" => {
            let left_false = narrowed(field(condition, "LHS"), false, vars);
            let left_true = narrowed(field(condition, "LHS"), true, vars);
            let right_false = narrowed(field(condition, "RHS"), false, &left_true);
            merge(&left_false, &right_false)
        }
        "DMASTOr" if truth => {
            let left_true = narrowed(field(condition, "LHS"), true, vars);
            let left_false = narrowed(field(condition, "LHS"), false, vars);
            let right_true = narrowed(field(condition, "RHS"), true, &left_false);
            merge(&left_true, &right_true)
        }
        "DMASTOr" => {
            let left = narrowed(field(condition, "LHS"), false, vars);
            narrowed(field(condition, "RHS"), false, &left)
        }
        _ => {
            let mut result = vars.clone();
            if let Some((name, null_on_true)) = null_guard(condition) {
                if let Some(state) = vars.get(name) {
                    let exact_null_check =
                        matches!(kind(condition), "DMASTEqual" | "DMASTNotEqual");
                    let narrowed_null = if truth == null_on_true {
                        if exact_null_check || state.kind.starts_with('/') {
                            Nullability::Null
                        } else {
                            Nullability::Maybe
                        }
                    } else {
                        Nullability::NonNull
                    };
                    let alias_id = state.alias_id;
                    for (candidate, value) in &mut result {
                        if candidate == name || (alias_id != 0 && value.alias_id == alias_id) {
                            value.null = narrowed_null;
                        }
                    }
                }
            }
            result
        }
    }
}

fn static_literal(expr: &Value) -> bool {
    matches!(
        kind(expr),
        "DMASTConstantInteger"
            | "DMASTConstantFloat"
            | "DMASTConstantString"
            | "DMASTConstantNull"
            | "DMASTList"
            | "DMASTNewList"
            | "DMASTNewPath"
            | "DMASTNewModifiedType"
            | "DMASTNewExpr"
            | "DMASTNewInferred"
    )
}

fn declared_type(path: Option<&str>, value_type: Option<&str>) -> String {
    crate::symbols::declared_type(path, value_type)
}

struct ProcAnalysis<'a> {
    path: String,
    owner: String,
    proc_name: String,
    contracts: &'a [Contract],
    symbols: &'a Symbols,
    max_line: usize,
    return_type: String,
    nonnull_return: bool,
    nonnull_parameters: HashSet<String>,
    nullable_locals: HashSet<String>,
    untyped_locals: HashSet<String>,
    next_alias_id: u64,
    branches: usize,
    globals: HashSet<String>,
    global_writes: HashSet<String>,
    type_paths: HashSet<String>,
    findings: Vec<Finding>,
}

impl ProcAnalysis<'_> {
    fn literal_reflected_member(
        &self,
        lhs: &Value,
        vars: &HashMap<String, TypeState>,
    ) -> Option<(String, String)> {
        let lhs = unwrap_expression(lhs);
        if kind(lhs) != "DMASTDereference" {
            return None;
        }
        let receiver = unwrap_expression(field(lhs, "Expression"));
        let name = field(receiver, "Identifier").as_str()?;
        let operations = field(lhs, "Operations").as_array()?;
        let (receiver_type, index) =
            if name == "vars" && !vars.contains_key("vars") && operations.len() == 1 {
                (self.owner.clone(), &operations[0])
            } else if operations.len() == 2
                && kind(&operations[0]) == "FieldOperation"
                && field(&operations[0], "Identifier").as_str() == Some("vars")
            {
                let receiver_type = if name == "src" {
                    self.owner.clone()
                } else {
                    vars.get(name)?.kind.clone()
                };
                (receiver_type, &operations[1])
            } else {
                return None;
            };
        if kind(index) != "IndexOperation" {
            return None;
        }
        let key = field(index, "Index");
        if kind(key) != "DMASTConstantString" {
            return None;
        }
        Some((receiver_type, field(key, "Value").as_str()?.into()))
    }

    fn tracked_write(&mut self, node: &Value, lhs: &Value, vars: &HashMap<String, TypeState>) {
        let lhs = unwrap_expression(lhs);
        let reflected = self.literal_reflected_member(lhs, vars);
        let (receiver_type, member) = if let Some((receiver, member)) = &reflected {
            (receiver.clone(), member.as_str())
        } else if kind(lhs) == "DMASTIdentifier" {
            let member = field(lhs, "Identifier").as_str().unwrap_or("");
            if vars.contains_key(member) {
                return;
            }
            (self.owner.clone(), member)
        } else if kind(lhs) == "DMASTDereference" {
            let receiver = unwrap_expression(field(lhs, "Expression"));
            let Some(name) = field(receiver, "Identifier").as_str() else {
                return;
            };
            let receiver_type = if name == "src" {
                self.owner.clone()
            } else if let Some(state) = vars.get(name) {
                state.kind.clone()
            } else {
                return;
            };
            let Some(operations) = field(lhs, "Operations").as_array() else {
                return;
            };
            let member = if operations.len() == 1 && kind(&operations[0]) == "FieldOperation" {
                field(&operations[0], "Identifier").as_str()
            } else if operations.len() == 2
                && kind(&operations[0]) == "FieldOperation"
                && field(&operations[0], "Identifier").as_str() == Some("vars")
                && kind(&operations[1]) == "IndexOperation"
            {
                let key = field(&operations[1], "Index");
                if kind(key) == "DMASTConstantString" {
                    field(key, "Value").as_str()
                } else {
                    if self.contracts.iter().any(|c| {
                        c.visibility == Visibility::Tracked
                            && (receiver_type == c.owner
                                || receiver_type.starts_with(&format!("{}/", c.owner)))
                    }) {
                        self.finding(node, "tracked-dynamic-write", "error",
                            format!("dynamic vars[] write may bypass a tracked field on {receiver_type}"));
                    }
                    return;
                }
            } else {
                return;
            };
            let Some(member) = member else {
                return;
            };
            (receiver_type, member)
        } else {
            return;
        };
        let Some(contract) = self.member_contract(&receiver_type, member, Visibility::Tracked)
        else {
            return;
        };
        let setter = contract.value.as_deref().unwrap_or("");
        if self.owner != contract.owner || self.proc_name != setter {
            self.finding(
                node,
                "tracked-field-write",
                "error",
                format!(
                    "{}.{} is tracked; write through {}/{}()",
                    contract.owner, member, contract.owner, setter
                ),
            );
        }
    }
    fn inspect_condition(&mut self, condition: &Value, vars: &HashMap<String, TypeState>) {
        match kind(condition) {
            "DMASTAnd" => {
                self.inspect_condition(field(condition, "LHS"), vars);
                let left_true = narrowed(field(condition, "LHS"), true, vars);
                self.inspect_condition(field(condition, "RHS"), &left_true);
            }
            "DMASTOr" => {
                self.inspect_condition(field(condition, "LHS"), vars);
                let left_false = narrowed(field(condition, "LHS"), false, vars);
                self.inspect_condition(field(condition, "RHS"), &left_false);
            }
            _ => self.inspect(condition, vars),
        }
    }
    fn alias_for_assignment(&mut self, expression: &Value, value: &TypeState) -> u64 {
        if kind(expression) == "DMASTIdentifier" && value.alias_id != 0 {
            value.alias_id
        } else {
            self.next_alias_id += 1;
            self.next_alias_id
        }
    }
    fn check_call(
        &mut self,
        node: &Value,
        owner: &str,
        name: &str,
        parameters: &Value,
        vars: &HashMap<String, TypeState>,
    ) {
        let Some(signature) = self.symbols.proc(owner, name) else {
            return;
        };
        let Some(arguments) = parameters.as_array() else {
            return;
        };
        for (index, argument) in arguments.iter().enumerate() {
            if !field(argument, "Key").is_null() {
                continue;
            }
            let Some(parameter) = signature.parameters.get(index) else {
                break;
            };
            let expression = field(argument, "Value");
            let passed = value(expression, vars, self.symbols, &self.owner);
            if parameter.nonnull && passed.null == Nullability::Null {
                self.finding(
                    node,
                    "nonnull-argument",
                    "error",
                    format!("{owner}/{name}: {} receives null", parameter.name),
                );
            }
            if static_literal(expression)
                && !compatible(&parameter.kind, &passed.kind)
                && passed.kind != "unknown"
            {
                self.finding(
                    node,
                    "argument-type",
                    "warning",
                    format!(
                        "{owner}/{name}: {} receives {} instead of {}",
                        parameter.name, passed.kind, parameter.kind
                    ),
                );
            }
        }
    }
    fn member_contract(
        &self,
        receiver_type: &str,
        member: &str,
        visibility: Visibility,
    ) -> Option<&Contract> {
        self.contracts
            .iter()
            .filter(|contract| {
                contract.visibility == visibility
                    && contract.parameter.is_none()
                    && contract.member == member
                    && (receiver_type == contract.owner
                        || receiver_type.starts_with(&format!("{}/", contract.owner)))
            })
            .max_by_key(|contract| contract.owner.len())
    }
    fn access_contract(&self, receiver_type: &str, member: &str) -> Option<&Contract> {
        self.contracts
            .iter()
            .filter(|contract| {
                matches!(
                    contract.visibility,
                    Visibility::Public | Visibility::Private | Visibility::Protected
                ) && contract.parameter.is_none()
                    && contract.member == member
                    && (receiver_type == contract.owner
                        || receiver_type.starts_with(&format!("{}/", contract.owner)))
            })
            .max_by_key(|contract| contract.owner.len())
    }
    fn check_access(&mut self, node: &Value, receiver_type: &str, member: &str, display: &str) {
        if let Some(contract) = self.access_contract(receiver_type, member) {
            let permitted = match contract.visibility {
                Visibility::Public => true,
                Visibility::Private => self.owner == contract.owner,
                Visibility::Protected => {
                    self.owner == contract.owner
                        || self.owner.starts_with(&format!("{}/", contract.owner))
                }
                _ => true,
            };
            if !permitted {
                let owner = contract.owner.clone();
                let visibility = contract.visibility;
                self.finding(
                    node,
                    "restricted-member",
                    "warning",
                    format!("{display}.{member} is {visibility:?} to {owner}"),
                );
            }
        }
    }
    fn record_line(&mut self, node: &Value) {
        let (path, line) = location(node, &self.path);
        if path == self.path {
            self.max_line = self.max_line.max(line);
        }
    }
    fn finding(
        &mut self,
        node: &Value,
        rule: &'static str,
        severity: &'static str,
        message: String,
    ) {
        let (path, line) = location(node, &self.path);
        self.findings.push(Finding {
            rule,
            path,
            line,
            severity,
            message,
        });
    }
    fn inspect(&mut self, node: &Value, vars: &HashMap<String, TypeState>) {
        self.record_line(node);
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
            self.tracked_write(node, field(node, "LHS"), vars);
        }
        if matches!(kind(node), "DMASTDivide" | "DMASTDivideAssign")
            && constant_zero(field(node, "RHS"))
        {
            self.finding(
                node,
                "divide-by-zero",
                "error",
                "division by literal zero".into(),
            );
        }
        if kind(node) == "DMASTProcCall" {
            if let Some(name) = field(field(node, "Callable"), "Identifier").as_str() {
                let owner = self.owner.clone();
                self.check_call(node, &owner, name, field(node, "Parameters"), vars);
            }
        }
        if kind(node).starts_with("DMASTProcStatementIf")
            || matches!(
                kind(node),
                "DMASTProcStatementFor"
                    | "DMASTProcStatementWhile"
                    | "DMASTProcStatementDoWhile"
                    | "DMASTProcStatementSwitch"
                    | "DMASTProcStatementTryCatch"
            )
        {
            self.branches += 1;
        }
        if kind(node) == "DMASTDereference" {
            let receiver = unwrap_expression(field(node, "Expression"));
            if kind(receiver) == "DMASTIdentifier" {
                let name = field(receiver, "Identifier").as_str().unwrap_or("");
                let operations = field(node, "Operations").as_array();
                let safe = operations
                    .and_then(|ops| ops.first())
                    .and_then(|op| op["fields"]["Safe"].as_bool())
                    .unwrap_or(false);
                if !safe
                    && vars
                        .get(name)
                        .is_some_and(|state| state.null == Nullability::Null)
                {
                    self.finding(
                        node,
                        "null-deref",
                        "error",
                        format!("{name} is null on this path"),
                    );
                } else if !safe
                    && self.nullable_locals.contains(name)
                    && vars
                        .get(name)
                        .is_some_and(|state| state.null == Nullability::Maybe)
                {
                    self.finding(
                        node,
                        "maybe-null-deref",
                        "info",
                        format!("{name} may still be null on this path"),
                    );
                }
                if name == "GLOB" {
                    for op in operations.into_iter().flatten() {
                        if let Some(member) = op["fields"]["Identifier"].as_str() {
                            self.globals.insert(member.into());
                        }
                    }
                }
                let receiver_type = if name == "src" {
                    Some(self.owner.clone())
                } else {
                    vars.get(name).map(|state| state.kind.clone())
                };
                if let (Some(receiver_type), Some(operation)) = (
                    receiver_type.as_deref(),
                    operations.and_then(|ops| ops.first()),
                ) {
                    if let Some(member) = operation["fields"]["Identifier"].as_str() {
                        if kind(operation) == "CallOperation" {
                            self.check_call(
                                node,
                                receiver_type,
                                member,
                                field(operation, "Parameters"),
                                vars,
                            );
                        }
                        self.check_access(node, receiver_type, member, name);
                    }
                }
                let builtin_vars = name == "vars" && !vars.contains_key("vars");
                let index = if builtin_vars {
                    operations.and_then(|ops| ops.first())
                } else {
                    operations.and_then(|ops| {
                        (ops.len() == 2
                            && kind(&ops[0]) == "FieldOperation"
                            && field(&ops[0], "Identifier").as_str() == Some("vars"))
                        .then(|| &ops[1])
                    })
                };
                if let Some(index) = index.filter(|op| kind(op) == "IndexOperation") {
                    let key = field(index, "Index");
                    if kind(key) == "DMASTConstantString" {
                        if let Some(member) = field(key, "Value").as_str() {
                            let reflected_owner = if builtin_vars {
                                Some(self.owner.clone())
                            } else {
                                receiver_type.clone()
                            };
                            if let Some(reflected_owner) = reflected_owner {
                                self.check_access(node, &reflected_owner, member, name);
                            }
                        }
                    }
                }
            }
        }
        if kind(node) == "DMASTConstantPath" {
            if let Some(path) = field(field(node, "Value"), "Path").as_str() {
                self.type_paths.insert(path.into());
            }
        }
        for child in children(node) {
            self.inspect(child, vars);
        }
    }
    fn block(&mut self, block: &Value, vars: &mut HashMap<String, TypeState>) -> bool {
        let mut returns = false;
        if let Some(statements) = field(block, "Statements").as_array() {
            for statement in statements {
                if returns {
                    self.finding(
                        statement,
                        "unreachable-code",
                        "info",
                        "statement follows an unconditional return".into(),
                    );
                    break;
                }
                returns = self.statement(statement, vars);
            }
        }
        returns
    }
    fn statement(&mut self, node: &Value, vars: &mut HashMap<String, TypeState>) -> bool {
        self.record_line(node);
        match kind(node) {
            "DMASTProcStatementVarDeclaration" => {
                let name = field(node, "Name").as_str().unwrap_or("");
                let ty = declared_type(
                    field(node, "Type").as_str(),
                    field(node, "ValueType").as_str(),
                );
                let initial = field(node, "Value");
                self.inspect(initial, vars);
                let val = if initial.is_null() {
                    TypeState {
                        kind: "null".into(),
                        null: Nullability::Null,
                        alias_id: 0,
                    }
                } else {
                    value(initial, vars, self.symbols, &self.owner)
                };
                if val.null == Nullability::Null {
                    self.nullable_locals.insert(name.into());
                }
                if ty == "unknown" {
                    self.untyped_locals.insert(name.into());
                }
                if !compatible(&ty, &val.kind) && val.kind != "unknown" && static_literal(initial) {
                    self.finding(
                        node,
                        "type-assignment",
                        "warning",
                        format!("{name}: {} assigned to {ty}", val.kind),
                    );
                }
                vars.insert(
                    name.into(),
                    TypeState {
                        kind: if ty == "unknown" {
                            val.kind.clone()
                        } else {
                            ty
                        },
                        null: val.null,
                        alias_id: self.alias_for_assignment(initial, &val),
                    },
                );
                false
            }
            "DMASTProcStatementExpression" => {
                let expr = field(node, "Expression");
                if kind(expr) == "DMASTAssign" {
                    let lhs = field(expr, "LHS");
                    let rhs = field(expr, "RHS");
                    self.tracked_write(expr, lhs, vars);
                    if kind(lhs) == "DMASTIdentifier"
                        && kind(rhs) == "DMASTIdentifier"
                        && field(lhs, "Identifier") == field(rhs, "Identifier")
                    {
                        self.finding(
                            expr,
                            "self-assignment",
                            "info",
                            format!(
                                "{} is assigned to itself",
                                field(lhs, "Identifier").as_str().unwrap_or("value")
                            ),
                        );
                    }
                    self.inspect(rhs, vars);
                    if kind(lhs) == "DMASTIdentifier" {
                        let name = field(lhs, "Identifier").as_str().unwrap_or("");
                        if let Some(previous) = vars.get(name).cloned() {
                            let val = value(rhs, vars, self.symbols, &self.owner);
                            if self.nonnull_parameters.contains(name)
                                && val.null == Nullability::Null
                            {
                                self.finding(
                                    expr,
                                    "nonnull-parameter-assignment",
                                    "error",
                                    format!("{name} is declared nonnull"),
                                );
                            }
                            if !self.untyped_locals.contains(name)
                                && !compatible(&previous.kind, &val.kind)
                                && static_literal(rhs)
                            {
                                self.finding(
                                    expr,
                                    "type-assignment",
                                    "warning",
                                    format!("{name}: {} assigned to {}", val.kind, previous.kind),
                                );
                            }
                            vars.insert(
                                name.into(),
                                TypeState {
                                    kind: if self.untyped_locals.contains(name) {
                                        val.kind.clone()
                                    } else {
                                        previous.kind
                                    },
                                    null: val.null,
                                    alias_id: self.alias_for_assignment(rhs, &val),
                                },
                            );
                        }
                    } else {
                        if kind(lhs) == "DMASTDereference"
                            && kind(field(lhs, "Expression")) == "DMASTIdentifier"
                            && field(field(lhs, "Expression"), "Identifier").as_str()
                                == Some("GLOB")
                        {
                            let operations = field(lhs, "Operations").as_array();
                            let reflected = operations.and_then(|ops| {
                                if ops.len() != 2
                                    || kind(&ops[0]) != "FieldOperation"
                                    || field(&ops[0], "Identifier").as_str() != Some("vars")
                                    || kind(&ops[1]) != "IndexOperation"
                                {
                                    return None;
                                }
                                let key = field(&ops[1], "Index");
                                (kind(key) == "DMASTConstantString")
                                    .then(|| field(key, "Value").as_str())
                                    .flatten()
                            });
                            let direct = operations.and_then(|ops| {
                                (ops.len() == 1 && kind(&ops[0]) == "FieldOperation")
                                    .then(|| field(&ops[0], "Identifier").as_str())
                                    .flatten()
                            });
                            if let Some(member) = reflected.or(direct) {
                                self.global_writes.insert(member.into());
                                if self.contracts.iter().any(|contract| {
                                    contract.owner == "GLOB"
                                        && contract.member == member
                                        && contract.visibility == Visibility::ReadOnly
                                }) {
                                    self.finding(
                                        expr,
                                        "readonly-global-assignment",
                                        "error",
                                        format!("GLOB.{member} has a readonly binding"),
                                    );
                                }
                            }
                        }
                        if kind(lhs) == "DMASTDereference"
                            && value(rhs, vars, self.symbols, &self.owner).null == Nullability::Null
                        {
                            let receiver = unwrap_expression(field(lhs, "Expression"));
                            if kind(receiver) == "DMASTIdentifier" {
                                let name = field(receiver, "Identifier").as_str().unwrap_or("");
                                let reflected = self.literal_reflected_member(lhs, vars);
                                let direct_ty = if name == "src" {
                                    Some(self.owner.as_str())
                                } else {
                                    vars.get(name).map(|state| state.kind.as_str())
                                };
                                let direct_member = field(lhs, "Operations")
                                    .as_array()
                                    .and_then(|ops| ops.first())
                                    .filter(|op| kind(op) == "FieldOperation")
                                    .and_then(|op| op["fields"]["Identifier"].as_str());
                                let target = reflected
                                    .as_ref()
                                    .map(|(ty, member)| (ty.as_str(), member.as_str()))
                                    .or_else(|| direct_ty.zip(direct_member));
                                if let Some((ty, member)) = target {
                                    if self
                                        .member_contract(ty, member, Visibility::NonNull)
                                        .is_some()
                                    {
                                        self.finding(
                                            expr,
                                            "nonnull-assignment",
                                            "error",
                                            format!("{name}.{member} is declared nonnull"),
                                        );
                                    }
                                }
                            }
                        }
                        self.inspect(lhs, vars);
                    }
                } else {
                    self.inspect(expr, vars);
                }
                false
            }
            "DMASTProcStatementReturn" => {
                let expr = field(node, "Value");
                self.inspect(expr, vars);
                let returned = if expr.is_null() {
                    TypeState {
                        kind: "null".into(),
                        null: Nullability::Null,
                        alias_id: 0,
                    }
                } else {
                    value(expr, vars, self.symbols, &self.owner)
                };
                if self.nonnull_return && returned.null == Nullability::Null {
                    self.finding(
                        node,
                        "nonnull-return",
                        "error",
                        "proc declared nonnull returns null".into(),
                    );
                }
                if self.return_type != "unknown"
                    && !compatible(&self.return_type, &returned.kind)
                    && static_literal(expr)
                {
                    self.finding(
                        node,
                        "return-type",
                        "warning",
                        format!(
                            "{} returned from proc declared {}",
                            returned.kind, self.return_type
                        ),
                    );
                }
                true
            }
            "DMASTProcStatementIf" => {
                self.branches += 1;
                let condition = field(node, "Condition");
                self.inspect_condition(condition, vars);
                let mut then_vars = narrowed(condition, true, vars);
                let mut else_vars = narrowed(condition, false, vars);
                let then_return = self.block(field(node, "Body"), &mut then_vars);
                let else_return = if field(node, "ElseBody").is_null() {
                    false
                } else {
                    self.block(field(node, "ElseBody"), &mut else_vars)
                };
                *vars = if then_return {
                    else_vars
                } else if else_return {
                    then_vars
                } else {
                    merge(&then_vars, &else_vars)
                };
                then_return && else_return
            }
            "DMASTProcStatementFor"
            | "DMASTProcStatementWhile"
            | "DMASTProcStatementDoWhile"
            | "DMASTProcStatementSpawn"
            | "DMASTProcStatementInfLoop" => {
                self.branches += 1;
                for child in children(node) {
                    if kind(child) != "DMASTProcBlockInner" {
                        self.inspect(child, &HashMap::new());
                    }
                }
                let mut body_vars = vars.clone();
                for state in body_vars.values_mut() {
                    if state.null == Nullability::Null {
                        state.null = Nullability::Unknown;
                    }
                }
                self.block(field(node, "Body"), &mut body_vars);
                *vars = merge(vars, &body_vars);
                false
            }
            _ => {
                self.inspect(node, vars);
                false
            }
        }
    }
}

fn direct_parent_call(expr: &Value, pure_arguments: bool) -> bool {
    let expr = unwrap_expression(expr);
    if kind(expr) == "DMASTProcCall" {
        return kind(field(expr, "Callable")) == "DMASTCallableSuper"
            && (!pure_arguments
                || field(expr, "Parameters").as_array().is_some_and(|args| {
                    args.iter().all(|arg| {
                        let value = unwrap_expression(field(arg, "Value"));
                        matches!(
                            kind(value),
                            "DMASTIdentifier"
                                | "DMASTConstantNull"
                                | "DMASTConstantInteger"
                                | "DMASTConstantFloat"
                                | "DMASTConstantString"
                                | "DMASTConstantPath"
                        )
                    })
                }));
    }
    kind(expr) == "DMASTAssign"
        && kind(field(expr, "LHS")) == "DMASTCallableSelf"
        && direct_parent_call(field(expr, "RHS"), pure_arguments)
}

fn starts_with_parent_call(statement: &Value, pure_arguments: bool) -> bool {
    match kind(statement) {
        "DMASTProcStatementExpression" | "DMASTProcStatementReturn" => {
            let expr = if kind(statement) == "DMASTProcStatementReturn" {
                field(statement, "Value")
            } else {
                field(statement, "Expression")
            };
            direct_parent_call(expr, pure_arguments)
        }
        "DMASTProcStatementIf" => direct_parent_call(field(statement, "Condition"), pure_arguments),
        _ => false,
    }
}

// The two bits represent paths that have not called the parent and paths that
// have. A return with the first bit set is an immediate contract violation.
fn parent_expression_paths(expr: &Value, mut paths: u8) -> u8 {
    if paths == 0 {
        return 0;
    }
    match kind(expr) {
        "DMASTExpressionWrapped" | "DMASTNot" | "DMASTBinaryNot" => {
            parent_expression_paths(field(expr, "Value"), paths)
        }
        "DMASTProcCall" => {
            for argument in field(expr, "Parameters").as_array().into_iter().flatten() {
                paths = parent_expression_paths(field(argument, "Value"), paths);
            }
            if kind(field(expr, "Callable")) == "DMASTCallableSuper" {
                2
            } else {
                paths
            }
        }
        "DMASTCall" => {
            for name in ["CallParameters", "ProcParameters"] {
                for argument in field(expr, name).as_array().into_iter().flatten() {
                    paths = parent_expression_paths(field(argument, "Value"), paths);
                }
            }
            paths
        }
        "DMASTAnd" | "DMASTOr" => {
            let left = parent_expression_paths(field(expr, "LHS"), paths);
            left | parent_expression_paths(field(expr, "RHS"), left)
        }
        "DMASTTernary" => {
            let condition = parent_expression_paths(field(expr, "Condition"), paths);
            parent_expression_paths(field(expr, "TrueExpr"), condition)
                | parent_expression_paths(field(expr, "FalseExpr"), condition)
        }
        "DMASTAssign" => {
            paths = parent_expression_paths(field(expr, "LHS"), paths);
            parent_expression_paths(field(expr, "RHS"), paths)
        }
        "DMASTDereference" => {
            paths = parent_expression_paths(field(expr, "Expression"), paths);
            for operation in field(expr, "Operations").as_array().into_iter().flatten() {
                paths = parent_expression_paths(field(operation, "Index"), paths);
                for argument in field(operation, "Parameters")
                    .as_array()
                    .into_iter()
                    .flatten()
                {
                    paths = parent_expression_paths(field(argument, "Value"), paths);
                }
            }
            paths
        }
        "DMASTList" | "DMASTNewList" => {
            let members = if kind(expr) == "DMASTList" {
                "Values"
            } else {
                "Parameters"
            };
            for argument in field(expr, members).as_array().into_iter().flatten() {
                paths = parent_expression_paths(field(argument, "Key"), paths);
                paths = parent_expression_paths(field(argument, "Value"), paths);
            }
            paths
        }
        "DMASTAdd"
        | "DMASTSubtract"
        | "DMASTMultiply"
        | "DMASTDivide"
        | "DMASTEqual"
        | "DMASTNotEqual"
        | "DMASTGreaterThan"
        | "DMASTLessThan"
        | "DMASTGreaterThanOrEqual"
        | "DMASTLessThanOrEqual"
        | "DMASTBinaryAnd"
        | "DMASTBinaryOr"
        | "DMASTBinaryXor"
        | "DMASTLeftShift"
        | "DMASTRightShift" => {
            paths = parent_expression_paths(field(expr, "LHS"), paths);
            parent_expression_paths(field(expr, "RHS"), paths)
        }
        _ => paths,
    }
}

fn parent_paths(block: &Value, mut paths: u8) -> (u8, bool) {
    let Some(statements) = field(block, "Statements").as_array() else {
        return (paths, false);
    };
    for statement in statements {
        if paths == 0 {
            break;
        }
        match kind(statement) {
            "DMASTProcStatementReturn" => {
                paths = parent_expression_paths(field(statement, "Value"), paths);
                if paths & 1 != 0 {
                    return (0, true);
                }
                paths = 0;
            }
            "DMASTProcStatementIf" => {
                paths = parent_expression_paths(field(statement, "Condition"), paths);
                let (then_paths, then_bad) = parent_paths(field(statement, "Body"), paths);
                let (else_paths, else_bad) = if field(statement, "ElseBody").is_null() {
                    (paths, false)
                } else {
                    parent_paths(field(statement, "ElseBody"), paths)
                };
                if then_bad || else_bad {
                    return (0, true);
                }
                paths = then_paths | else_paths;
            }
            "DMASTProcStatementFor"
            | "DMASTProcStatementWhile"
            | "DMASTProcStatementDoWhile"
            | "DMASTProcStatementSpawn"
            | "DMASTProcStatementInfLoop" => {
                // The body may execute zero times, or asynchronously for spawn.
                // Still inspect it for an early return without a parent call.
                let (_, bad) = parent_paths(field(statement, "Body"), paths);
                if bad {
                    return (0, true);
                }
            }
            "DMASTProcStatementExpression" => {
                paths = parent_expression_paths(field(statement, "Expression"), paths);
            }
            "DMASTProcStatementVarDeclaration" => {
                paths = parent_expression_paths(field(statement, "Value"), paths);
            }
            other
                if other.starts_with("DMASTProcStatement")
                    && !matches!(
                        other,
                        "DMASTProcStatementExpression" | "DMASTProcStatementVarDeclaration"
                    )
                    && paths & 1 != 0 =>
            {
                // Switch, try and other control flow are not currently proved.
                // A preceding parent call is sufficient regardless of their shape.
                return (0, true);
            }
            _ => {}
        }
    }
    (paths, false)
}

fn parent_always_finding(
    item: &Value,
    contracts: &[Contract],
    symbols: &Symbols,
) -> Option<Finding> {
    let owner = item["owner"].as_str()?;
    let name = item["name"].as_str()?;
    if matches!(name, "Destroy" | "Del") {
        return None;
    }
    let local = contracts.iter().any(|contract| {
        contract.owner == owner
            && contract.member == name
            && contract.parameter.is_none()
            && contract.visibility == Visibility::ParentAlways
    });
    let locally_exempt = contracts.iter().any(|contract| {
        contract.owner == owner
            && contract.member == name
            && contract.visibility == Visibility::ParentExemptOverride
    });
    let mut inherited = false;
    let mut ancestor = symbols.parent(owner);
    let mut visited = std::collections::HashSet::new();
    while let Some(parent) = ancestor {
        if !visited.insert(parent.clone()) {
            break;
        }
        let policy = contracts.iter().rev().find(|contract| {
            contract.owner == parent
                && contract.member == name
                && matches!(
                    contract.visibility,
                    Visibility::ParentRequiredByOverrides | Visibility::ParentExemptOverride
                )
        });
        if let Some(contract) = policy {
            inherited = contract.visibility == Visibility::ParentRequiredByOverrides;
            break;
        }
        ancestor = symbols.parent(&parent);
    }
    if !local && (!inherited || locally_exempt) {
        return None;
    }
    let (surviving, failed_return) = parent_paths(&item["body"], 1);
    if !failed_return && surviving & 1 == 0 {
        return None;
    }
    let (path, line) = location(item, "<unknown>");
    Some(Finding {
        rule: "parent-always",
        path,
        line,
        severity: "error",
        message: format!("{owner}/{name} must call ..() on every normal path"),
    })
}

fn parent_first_finding(item: &Value, contracts: &[Contract]) -> Option<Finding> {
    let owner = item["owner"].as_str()?;
    let name = item["name"].as_str()?;
    if !contracts.iter().any(|contract| {
        contract.owner == owner
            && contract.member == name
            && contract.parameter.is_none()
            && contract.visibility == Visibility::ParentFirst
    }) {
        return None;
    }
    let first = item["body"]["fields"]["Statements"]
        .as_array()
        .and_then(|statements| statements.first());
    if first.is_some_and(|statement| starts_with_parent_call(statement, true)) {
        return None;
    }
    let (path, line) = first
        .map(|node| location(node, item["file"].as_str().unwrap_or("<unknown>")))
        .unwrap_or_else(|| location(item, "<unknown>"));
    Some(Finding {
        rule: "parent-first",
        path,
        line,
        severity: "error",
        message: format!("{owner}/{name} must call ..() before other work on every path"),
    })
}

pub fn analyze_reader<R: BufRead>(reader: R, contracts: &[Contract]) -> io::Result<Vec<Finding>> {
    analyze_reader_with_symbols(reader, contracts, &Symbols::default())
}

pub fn analyze_reader_with_symbols<R: BufRead>(
    reader: R,
    contracts: &[Contract],
    symbols: &Symbols,
) -> io::Result<Vec<Finding>> {
    analyze_reader_with_symbols_in_files(reader, contracts, symbols, None)
}

pub fn analyze_reader_with_symbols_in_files<R: BufRead>(
    reader: R,
    contracts: &[Contract],
    symbols: &Symbols,
    included: Option<&HashSet<String>>,
) -> io::Result<Vec<Finding>> {
    let mut findings = Vec::new();
    let mut global_writers: HashMap<String, Vec<(String, usize)>> = HashMap::new();
    for line in reader.lines() {
        let line = line?;
        let mut deserializer = serde_json::Deserializer::from_str(&line);
        deserializer.disable_recursion_limit();
        let item: Value = Value::deserialize(&mut deserializer)?;
        if included.is_some_and(|files| {
            !item["file"]
                .as_str()
                .is_some_and(|path| files.contains(&path.replace('\\', "/")))
        }) {
            continue;
        }
        if string(&item["kind"]) != Some("proc") {
            if string(&item["kind"]) == Some("field") {
                let owner = item["owner"].as_str().unwrap_or("");
                let name = item["name"].as_str().unwrap_or("");
                for contract in contracts.iter().filter(|c| {
                    c.owner == owner && c.member == name && c.visibility == Visibility::Tracked
                }) {
                    if symbols.field(owner, name).is_some()
                        && symbols
                            .proc(owner, contract.value.as_deref().unwrap_or(""))
                            .is_none()
                    {
                        let (path, line) = location(&item, "<unknown>");
                        findings.push(Finding {
                            rule: "tracked-missing-setter",
                            path,
                            line,
                            severity: "error",
                            message: format!(
                                "{owner}.{name} declares missing setter {}()",
                                contract.value.as_deref().unwrap_or("")
                            ),
                        });
                    }
                }
                if contracts.iter().any(|contract| {
                    contract.owner == owner
                        && contract.member == name
                        && contract.visibility == Visibility::NonNull
                        && contract.parameter.is_none()
                }) && (item["initializer"].is_null()
                    || kind(&item["initializer"]) == "DMASTConstantNull")
                {
                    let (path, line) = location(&item, "<unknown>");
                    findings.push(Finding {
                        rule: "nonnull-initializer",
                        path,
                        line,
                        severity: "error",
                        message: format!("{owner}.{name} is declared nonnull but starts null"),
                    });
                }
            }
            continue;
        }
        if let Some(finding) = parent_first_finding(&item, contracts) {
            findings.push(finding);
        }
        if let Some(finding) = parent_always_finding(&item, contracts, symbols) {
            findings.push(finding);
        }
        let owner = item["owner"].as_str().unwrap_or("");
        let name = item["name"].as_str().unwrap_or("");
        if contracts.iter().any(|contract| {
            contract.owner == owner
                && contract.member == name
                && contract.visibility == Visibility::NoSleep
        }) {
            let mut calls = Vec::new();
            sleep_calls(
                &item["body"],
                item["file"].as_str().unwrap_or("<unknown>"),
                &mut calls,
            );
            findings.extend(calls.into_iter().map(|(path, line)| Finding {
                rule: "no-sleep",
                path,
                line,
                severity: "error",
                message: format!("{owner}/{name} declares no-sleep but calls sleep()"),
            }));
        }
        if contracts.iter().any(|c| {
            c.owner == owner
                && c.visibility == Visibility::Tracked
                && c.value.as_deref() == Some(name)
        }) && !calls_named(&item["body"], "om_mark_changed")
        {
            let (path, line) = location(&item, "<unknown>");
            findings.push(Finding {
                rule: "tracked-setter-not-marked",
                path,
                line,
                severity: "error",
                message: format!("{owner}/{name} must call om_mark_changed()"),
            });
        }
        let (path, number) = location(&item, "<unknown>");
        let mut state = ProcAnalysis {
            path: path.clone(),
            owner: item["owner"].as_str().unwrap_or("").into(),
            proc_name: item["name"].as_str().unwrap_or("").into(),
            contracts,
            symbols,
            max_line: number,
            return_type: declared_type(None, item["returnType"].as_str()),
            nonnull_return: contracts.iter().any(|contract| {
                contract.owner == item["owner"].as_str().unwrap_or("")
                    && contract.member == item["name"].as_str().unwrap_or("")
                    && contract.visibility == Visibility::NonNull
                    && contract.parameter.is_none()
            }),
            nonnull_parameters: contracts
                .iter()
                .filter(|contract| {
                    contract.owner == item["owner"].as_str().unwrap_or("")
                        && contract.member == item["name"].as_str().unwrap_or("")
                        && contract.visibility == Visibility::NonNull
                })
                .filter_map(|contract| contract.parameter.clone())
                .collect(),
            nullable_locals: HashSet::new(),
            untyped_locals: HashSet::new(),
            next_alias_id: 0,
            branches: 0,
            globals: HashSet::new(),
            global_writes: HashSet::new(),
            type_paths: HashSet::new(),
            findings: Vec::new(),
        };
        let mut vars = HashMap::new();
        if let Some(parameters) = item["parameters"].as_array() {
            for parameter in parameters {
                if let Some(name) = parameter["Name"].as_str() {
                    if state.nonnull_parameters.contains(name)
                        && kind(&parameter["defaultValue"]) == "DMASTConstantNull"
                    {
                        state.finding(
                            &item,
                            "nonnull-parameter-default",
                            "error",
                            format!("parameter {name} is declared nonnull but defaults to null"),
                        );
                    }
                    vars.insert(
                        name.into(),
                        TypeState {
                            kind: declared_type(
                                parameter["type"].as_str(),
                                parameter["valueType"].as_str(),
                            ),
                            null: if state.nonnull_parameters.contains(name) {
                                Nullability::NonNull
                            } else {
                                Nullability::Maybe
                            },
                            alias_id: {
                                state.next_alias_id += 1;
                                state.next_alias_id
                            },
                        },
                    );
                }
            }
        }
        state.block(&item["body"], &mut vars);
        let length = state.max_line.saturating_sub(number) + 1;
        if length > 160 {
            findings.push(Finding {
                rule: "large-proc",
                path: path.clone(),
                line: number,
                severity: "info",
                message: format!("{length} lines; threshold 160"),
            });
        }
        if length > 160 && state.branches >= 20 && state.globals.len() >= 4 {
            findings.push(Finding {
                rule: "god-proc",
                path: path.clone(),
                line: number,
                severity: "info",
                message: format!(
                    "{} branches, {} distinct globals",
                    state.branches,
                    state.globals.len()
                ),
            });
        }
        if state.globals.len() >= 10 {
            findings.push(Finding {
                rule: "global-coupling",
                path: path.clone(),
                line: number,
                severity: "info",
                message: format!("{} distinct GLOB fields", state.globals.len()),
            });
        }
        for global in &state.global_writes {
            global_writers
                .entry(global.clone())
                .or_default()
                .push((path.clone(), number));
        }
        if state.type_paths.len() >= 12 {
            findings.push(Finding {
                rule: "type-coupling",
                path: path.clone(),
                line: number,
                severity: "info",
                message: format!("{} distinct type paths", state.type_paths.len()),
            });
        }
        findings.extend(state.findings);
    }
    for (global, writers) in global_writers {
        if writers.len() >= 12 {
            let (path, line) = &writers[0];
            findings.push(Finding {
                rule: "widely-written-global",
                path: path.clone(),
                line: *line,
                severity: "info",
                message: format!("GLOB.{global} is written by {} procs", writers.len()),
            });
        }
    }
    Ok(findings)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tracked_field_requires_declaring_setter_even_for_subtypes_and_aliases() {
        let contracts = crate::contracts::collect(
            "// dm-health: tracked(setter=set_charge)\n/datum/cell/var/charge\n",
        );
        let field = |receiver: &str| {
            serde_json::json!({"kind":"DMASTDereference","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":receiver}},
                "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"charge","Safe":false}}]
            }})
        };
        let assignment = |lhs: Value| {
            serde_json::json!({"kind":"DMASTProcStatementExpression","file":"x.dm","line":3,"fields":{
                "Expression":{"kind":"DMASTAssign","file":"x.dm","line":3,"fields":{"LHS":lhs,
                    "RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}
            }})
        };
        let proc = |owner: &str, name: &str, parameter_type: Option<&str>, lhs: Value| {
            let parameters = parameter_type.map_or_else(Vec::new, |ty| {
                vec![serde_json::json!({"Name":"cell","type":ty})]
            });
            serde_json::json!({"kind":"proc","owner":owner,"name":name,"file":"x.dm","line":1,
                "parameters":parameters,"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[assignment(lhs)]}}})
        };
        let cases = [
            (proc("/datum/cell", "drain", None, field("src")), true),
            (proc("/datum/cell", "set_charge", None, field("src")), false),
            (
                proc("/datum/cell/subtype", "set_charge", None, field("src")),
                true,
            ),
            (
                proc("/datum/charger", "run", Some("/datum/cell"), field("cell")),
                true,
            ),
        ];
        for (item, expected) in cases {
            let findings = analyze_reader(format!("{item}\n").as_bytes(), &contracts).unwrap();
            assert_eq!(
                findings.iter().any(|f| f.rule == "tracked-field-write"),
                expected,
                "{item}"
            );
        }
    }
    #[test]
    fn tracked_field_rejects_reflective_writes() {
        let contracts = crate::contracts::collect(
            "// dm-health: tracked(setter=set_charge)\n/datum/cell/var/charge\n",
        );
        for (index, rule) in [
            (
                serde_json::json!({"kind":"DMASTConstantString","fields":{"Value":"charge"}}),
                "tracked-field-write",
            ),
            (
                serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"key"}}),
                "tracked-dynamic-write",
            ),
        ] {
            let lhs = serde_json::json!({"kind":"DMASTDereference","fields":{
                "Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},
                "Operations":[{"kind":"FieldOperation","fields":{"Identifier":"vars"}},
                    {"kind":"IndexOperation","fields":{"Index":index}}]
            }});
            let item = serde_json::json!({"kind":"proc","owner":"/datum/cell","name":"bypass","file":"x.dm","line":1,"parameters":[],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
                {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                    "kind":"DMASTAssign","fields":{"LHS":lhs,"RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}
                }}}
            ]}}});
            let findings = analyze_reader(format!("{item}\n").as_bytes(), &contracts).unwrap();
            assert!(findings.iter().any(|f| f.rule == rule), "{item}");
        }
    }
    #[test]
    fn dynamic_new_does_not_inherit_path_variable_type() {
        let expression = serde_json::json!({"kind":"DMASTNewExpr","fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"path"}}}});
        let variables = HashMap::from([(
            "path".into(),
            TypeState {
                kind: "/datum/material".into(),
                null: Nullability::NonNull,
                alias_id: 0,
            },
        )]);
        let result = value(&expression, &variables, &Symbols::default(), "/datum");
        assert_eq!(result.kind, "unknown");
        assert_eq!(result.null, Nullability::NonNull);
    }
    #[test]
    fn ast_null_flow() {
        let input = r#"{"kind":"proc","file":"x.dm","line":1,"parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementVarDeclaration","file":"x.dm","line":2,"fields":{"Name":"A","Type":"/mob","Value":{"kind":"DMASTConstantNull"}}},{"kind":"DMASTProcStatementReturn","file":"x.dm","line":3,"fields":{"Value":{"kind":"DMASTDereference","file":"x.dm","line":3,"fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"A"}},"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"name","Safe":false}}]}}}}]}}}"#;
        let findings = analyze_reader(input.as_bytes(), &[]).unwrap();
        assert_eq!(findings[0].rule, "null-deref");
    }

    #[test]
    fn ast_private_member_access() {
        let input = r#"{"kind":"proc","owner":"/datum/other","file":"x.dm","line":1,"parameters":[{"Name":"V","type":"/datum/vault"}],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementReturn","file":"x.dm","line":2,"fields":{"Value":{"kind":"DMASTDereference","file":"x.dm","line":2,"fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"V"}},"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"key","Safe":false}}]}}}}]}}}"#;
        let contracts = crate::contracts::collect("// dm-health: private\n/datum/vault/var/key\n");
        let findings = analyze_reader(input.as_bytes(), &contracts).unwrap();
        assert_eq!(findings[0].rule, "restricted-member");
    }

    #[test]
    fn literal_vars_index_obeys_private_contract() {
        let read = serde_json::json!({"kind":"DMASTDereference","file":"x.dm","line":2,
            "fields":{"Expression":{"kind":"DMASTIdentifier",
                "fields":{"Identifier":"V"}},"Operations":[
                    {"kind":"FieldOperation","fields":{"Identifier":"vars","Safe":false}},
                    {"kind":"IndexOperation","fields":{"Index":{
                        "kind":"DMASTConstantString","fields":{"Value":"key"}},
                        "Safe":false}}]}});
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/other","file":"x.dm",
        "line":1,"parameters":[{"Name":"V","type":"/datum/vault"}],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementReturn","file":"x.dm","line":2,
                "fields":{"Value":read}}
        ]}}});
        let contracts = crate::contracts::collect("// dm-health: private\n/datum/vault/var/key\n");
        let findings = analyze_reader(proc.to_string().as_bytes(), &contracts).unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "restricted-member" && finding.message.contains("key")));
    }

    #[test]
    fn explicit_public_on_subtype_overrides_private_parent() {
        let input = r#"{"kind":"proc","owner":"/datum/other","file":"x.dm","line":1,"parameters":[{"Name":"V","type":"/datum/vault/open"}],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementReturn","file":"x.dm","line":2,"fields":{"Value":{"kind":"DMASTDereference","file":"x.dm","line":2,"fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"V"}},"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"key","Safe":false}}]}}}}]}}}"#;
        let contracts = crate::contracts::collect(
            "// private\n/datum/vault/var/key\n// public\n/datum/vault/open/var/key\n",
        );
        let findings = analyze_reader(input.as_bytes(), &contracts).unwrap();
        assert!(!findings.iter().any(|f| f.rule == "restricted-member"));
    }

    #[test]
    fn ast_nonnull_assignment() {
        let input = r#"{"kind":"proc","owner":"/datum/vault","file":"x.dm","line":1,"parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementExpression","file":"x.dm","line":2,"fields":{"Expression":{"kind":"DMASTAssign","file":"x.dm","line":2,"fields":{"LHS":{"kind":"DMASTDereference","fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"src"}},"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"key","Safe":false}}]}},"RHS":{"kind":"DMASTConstantNull"}}}}}]}}}"#;
        let contracts = crate::contracts::collect("// dm-health: nonnull\n/datum/vault/var/key\n");
        let findings = analyze_reader(input.as_bytes(), &contracts).unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "nonnull-assignment"));
        let mut reflected: Value = serde_json::from_str(input).unwrap();
        reflected["body"]["fields"]["Statements"][0]["fields"]["Expression"]["fields"]["LHS"]
            ["fields"]["Operations"] = serde_json::json!([
            {"kind":"FieldOperation","fields":{"Identifier":"vars","Safe":false}},
            {"kind":"IndexOperation","fields":{"Index":{
                "kind":"DMASTConstantString","fields":{"Value":"key"}},
                "Safe":false}}
        ]);
        let reflected_findings =
            analyze_reader(reflected.to_string().as_bytes(), &contracts).unwrap();
        assert!(reflected_findings
            .iter()
            .any(|finding| finding.rule == "nonnull-assignment"));
    }

    #[test]
    fn nonnull_field_and_return_contracts() {
        let input = concat!(
            "{\"kind\":\"field\",\"owner\":\"/datum/vault\",\"name\":\"key\",\"file\":\"x.dm\",\"line\":2,\"initializer\":null}\n",
            "{\"kind\":\"proc\",\"owner\":\"/datum/vault\",\"name\":\"GetKey\",\"file\":\"x.dm\",\"line\":4,\"parameters\":[],\"body\":{\"kind\":\"DMASTProcBlockInner\",\"fields\":{\"Statements\":[{\"kind\":\"DMASTProcStatementReturn\",\"file\":\"x.dm\",\"line\":5,\"fields\":{\"Value\":{\"kind\":\"DMASTConstantNull\"}}}]}}}"
        );
        let contracts = crate::contracts::collect(
            "// dm-health: nonnull\n/datum/vault/var/key\n// dm-health: nonnull\n/datum/vault/proc/GetKey()\n",
        );
        let findings = analyze_reader(input.as_bytes(), &contracts).unwrap();
        assert!(findings.iter().any(|f| f.rule == "nonnull-initializer"));
        assert!(findings.iter().any(|f| f.rule == "nonnull-return"));
    }

    #[test]
    fn annotated_parameter_rejects_null_call() {
        let input = concat!(
            "{\"kind\":\"proc\",\"owner\":\"/datum\",\"name\":\"Take\",\"file\":\"x.dm\",\"line\":1,\"parameters\":[{\"Name\":\"item\",\"type\":\"/obj\",\"defaultValue\":null}],\"body\":null}\n",
            "{\"kind\":\"proc\",\"owner\":\"/datum\",\"name\":\"Test\",\"file\":\"x.dm\",\"line\":3,\"parameters\":[],\"body\":{\"kind\":\"DMASTProcBlockInner\",\"fields\":{\"Statements\":[{\"kind\":\"DMASTProcStatementExpression\",\"file\":\"x.dm\",\"line\":4,\"fields\":{\"Expression\":{\"kind\":\"DMASTProcCall\",\"file\":\"x.dm\",\"line\":4,\"fields\":{\"Callable\":{\"kind\":\"DMASTCallableProcIdentifier\",\"fields\":{\"Identifier\":\"Take\"}},\"Parameters\":[{\"kind\":\"DMASTCallParameter\",\"fields\":{\"Value\":{\"kind\":\"DMASTConstantNull\"},\"Key\":null}}]}}}}]}}}"
        );
        let contracts =
            crate::contracts::collect("// dm-health: nonnull(item)\n/datum/proc/Take(obj/item)\n");
        let symbols = Symbols::collect(input.as_bytes(), &contracts).unwrap();
        let findings = analyze_reader_with_symbols(input.as_bytes(), &contracts, &symbols).unwrap();
        assert!(findings.iter().any(|f| f.rule == "nonnull-argument"));
    }

    #[test]
    fn equality_null_guard_narrows_both_paths() {
        let condition: Value = serde_json::from_str(r#"{"kind":"DMASTEqual","fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"item"}},"RHS":{"kind":"DMASTConstantNull"}}}"#).unwrap();
        assert_eq!(null_guard(&condition), Some(("item", true)));
    }

    #[test]
    fn built_in_dm_type_hierarchy() {
        assert!(compatible("/atom/movable", "/obj/item/stack"));
        assert!(compatible("/atom", "/turf/simulated"));
        assert!(compatible("/datum", "/mob/living"));
        assert!(!compatible("/mob", "/obj/item"));
    }

    #[test]
    fn alias_and_short_circuit_guards_narrow_local_references() {
        let mut vars = HashMap::new();
        for name in ["a", "b"] {
            vars.insert(
                name.into(),
                TypeState {
                    kind: "/datum".into(),
                    null: Nullability::Maybe,
                    alias_id: 7,
                },
            );
        }
        let guard = serde_json::json!({"kind":"DMASTAnd","fields":{
            "LHS":{"kind":"DMASTNotEqual","fields":{"LHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"a"}},"RHS":{"kind":"DMASTConstantNull"}}},
            "RHS":{"kind":"DMASTIdentifier","fields":{"Identifier":"b"}}
        }});
        let yes = narrowed(&guard, true, &vars);
        assert_eq!(yes["a"].null, Nullability::NonNull);
        assert_eq!(yes["b"].null, Nullability::NonNull);
        let numeric = HashMap::from([(
            "n".into(),
            TypeState {
                kind: "num".into(),
                null: Nullability::Maybe,
                alias_id: 1,
            },
        )]);
        let test = serde_json::json!({"kind":"DMASTIdentifier","fields":{"Identifier":"n"}});
        assert_eq!(
            narrowed(&test, false, &numeric)["n"].null,
            Nullability::Maybe
        );
    }

    #[test]
    fn readonly_global_binding_rejects_direct_write() {
        let input = r#"{"kind":"proc","owner":"/datum","name":"Reset","file":"x.dm","line":1,"parameters":[],"body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[{"kind":"DMASTProcStatementExpression","file":"x.dm","line":2,"fields":{"Expression":{"kind":"DMASTAssign","file":"x.dm","line":2,"fields":{"LHS":{"kind":"DMASTDereference","fields":{"Expression":{"kind":"DMASTIdentifier","fields":{"Identifier":"GLOB"}},"Operations":[{"kind":"FieldOperation","fields":{"Identifier":"counter","Safe":false}}]}},"RHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}}}}}}]}}}"#;
        let contracts =
            crate::contracts::collect("// dm-health: readonly\nGLOBAL_VAR_INIT(counter, 0)\n");
        let findings = analyze_reader(input.as_bytes(), &contracts).unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "readonly-global-assignment"));
        let mut reflected: Value = serde_json::from_str(input).unwrap();
        reflected["body"]["fields"]["Statements"][0]["fields"]["Expression"]["fields"]["LHS"]
            ["fields"]["Operations"] = serde_json::json!([
            {"kind":"FieldOperation","fields":{"Identifier":"vars","Safe":false}},
            {"kind":"IndexOperation","fields":{"Index":{
                "kind":"DMASTConstantString","fields":{"Value":"counter"}},
                "Safe":false}}
        ]);
        let reflected_findings =
            analyze_reader(reflected.to_string().as_bytes(), &contracts).unwrap();
        assert!(reflected_findings
            .iter()
            .any(|finding| finding.rule == "readonly-global-assignment"));
    }

    #[test]
    fn no_sleep_contract_flags_direct_sleep_at_call_line() {
        let contracts =
            crate::contracts::collect("// dm-health: no-sleep\n/datum/test/proc/Run()\n");
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/test",
        "name":"Run","file":"x.dm","line":1,"parameters":[],
        "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[
            {"kind":"DMASTProcStatementExpression","fields":{"Expression":{
                "kind":"DMASTProcCall","file":"x.dm","line":7,"fields":{
                    "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"sleep"}},
                    "Parameters":[]}}}}
        ]}}});
        let findings = analyze_reader(proc.to_string().as_bytes(), &contracts).unwrap();
        assert!(findings.iter().any(|finding| finding.rule == "no-sleep"
            && finding.line == 7
            && finding.severity == "error"));
    }

    #[test]
    fn parent_first_contract_checks_every_path_and_order() {
        let contracts = crate::contracts::collect(
            "// dm-health: parent-first\n/datum/child/proc/Initialize()\n",
        );
        let parent = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableSuper","fields":{}},"Parameters":[]
        }});
        let direct = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":parent
        }});
        let late = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
            "Condition":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[direct.clone()]}},
            "ElseBody":null
        }});
        for (statements, should_fail) in [
            (vec![direct.clone()], false),
            (vec![late], true),
            (
                vec![
                    serde_json::json!({"kind":"DMASTProcStatementReturn","fields":{"Value":null}}),
                ],
                true,
            ),
            (vec![], true),
        ] {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/child",
                "name":"Initialize","file":"x.dm","line":1,"parameters":[],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":statements}}});
            let findings = analyze_reader(proc.to_string().as_bytes(), &contracts).unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "parent-first"),
                should_fail,
            );
        }
    }

    #[test]
    fn parent_always_accepts_late_call_but_rejects_missing_branch() {
        let contracts = crate::contracts::collect(
            "// dm-health: parent-always\n/datum/child/proc/Initialize()\n",
        );
        let parent = serde_json::json!({"kind":"DMASTProcCall","fields":{
            "Callable":{"kind":"DMASTCallableSuper","fields":{}},"Parameters":[]
        }});
        let call = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":parent.clone()
        }});
        let work = serde_json::json!({"kind":"DMASTProcStatementExpression","fields":{
            "Expression":{"kind":"DMASTConstantInteger","fields":{"Value":1}}
        }});
        let conditional = serde_json::json!({"kind":"DMASTProcStatementIf","fields":{
            "Condition":{"kind":"DMASTIdentifier","fields":{"Identifier":"flag"}},
            "Body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[call.clone()]}},
            "ElseBody":null
        }});
        for (statements, fail) in [
            (vec![work.clone(), call.clone()], false),
            (vec![conditional.clone()], true),
            (vec![conditional, call.clone()], false),
            (
                vec![
                    serde_json::json!({"kind":"DMASTProcStatementReturn","fields":{"Value":null}}),
                    call,
                ],
                true,
            ),
        ] {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/child",
                "name":"Initialize","file":"x.dm","line":1,"parameters":[],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":statements}}});
            let findings = analyze_reader(proc.to_string().as_bytes(), &contracts).unwrap();
            assert_eq!(
                findings
                    .iter()
                    .any(|finding| finding.rule == "parent-always"),
                fail
            );
        }
        let nested = serde_json::json!({"kind":"DMASTProcStatementReturn","fields":{
            "Value":{"kind":"DMASTProcCall","fields":{
                "Callable":{"kind":"DMASTCallableProcIdentifier","fields":{"Identifier":"wrap"}},
                "Parameters":[{"kind":"DMASTCallParameter","fields":{"Value":parent.clone(),"Key":null}}]
            }}
        }});
        let short_circuit = serde_json::json!({"kind":"DMASTProcStatementReturn","fields":{
            "Value":{"kind":"DMASTOr","fields":{
                "LHS":{"kind":"DMASTConstantInteger","fields":{"Value":1}},
                "RHS":parent
            }}
        }});
        for (statement, fails) in [(nested, false), (short_circuit, true)] {
            let proc = serde_json::json!({"kind":"proc","owner":"/datum/child",
                "name":"Initialize","file":"x.dm","line":1,"parameters":[],
                "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[statement]}}});
            let findings = analyze_reader(proc.to_string().as_bytes(), &contracts).unwrap();
            assert_eq!(findings.iter().any(|f| f.rule == "parent-always"), fails);
        }
    }
    #[test]
    fn existing_parent_pragma_is_inherited_by_override() {
        let contracts = crate::contracts::collect(
            "/datum/base/proc/Run()\n\tSHOULD_CALL_PARENT(TRUE)\n\treturn 1\n",
        );
        let proc = serde_json::json!({"kind":"proc","owner":"/datum/base/child",
            "name":"Run","file":"x.dm","line":1,"parameters":[],
            "body":{"kind":"DMASTProcBlockInner","fields":{"Statements":[]}}});
        let findings = analyze_reader(proc.to_string().as_bytes(), &contracts).unwrap();
        assert!(findings
            .iter()
            .any(|finding| finding.rule == "parent-always"));
        let exempt = crate::contracts::collect(
            "/datum/base/proc/Run()\n\tSHOULD_CALL_PARENT(TRUE)\n/datum/base/child/Run()\n\tSHOULD_CALL_PARENT(FALSE)\n",
        );
        let findings = analyze_reader(proc.to_string().as_bytes(), &exempt).unwrap();
        assert!(!findings
            .iter()
            .any(|finding| finding.rule == "parent-always"));
    }
}
