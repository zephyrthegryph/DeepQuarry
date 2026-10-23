//! The ledger events and the initializer references that `startup_order` orders.
use crate::startup_order::{EventKind, OrderEvent, Ref};
use dm_ir::SymbolId;
use dm_syntax::{Expr, ExprKind};
use dm_tree::allocation_ledger::{AllocationKind, AllocationLedger, NamespaceKind};
use std::collections::HashMap;

/// The allocation ledger as `startup_order` reads it, with the lookups the initializers need.
pub(crate) struct OrderEvents {
    pub events: Vec<OrderEvent>,
    /// Identity of the event table: equal digests are equal tables.
    pub digest: u128,
    procedures: HashMap<(SymbolId, SymbolId, bool), Vec<u32>>,
    fields: HashMap<(SymbolId, SymbolId), u32>,
}

impl OrderEvents {
    pub(crate) fn capture(ledger: &AllocationLedger, expanded_source: &str) -> Self {
        let mut events = Vec::with_capacity(ledger.events.len());
        let mut procedures: HashMap<(SymbolId, SymbolId, bool), Vec<u32>> = HashMap::new();
        let mut fields = HashMap::new();
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        let none = SymbolId::of("");
        for (index, event) in ledger.events.iter().enumerate() {
            let order = match event.kind {
                AllocationKind::Type { path, .. } => OrderEvent {
                    kind: EventKind::Type,
                    owner: path,
                    name: none,
                    formal: false,
                    verb: false,
                    target: None,
                },
                AllocationKind::Namespace { owner, kind, .. } => OrderEvent {
                    kind: EventKind::Namespace,
                    owner,
                    name: none,
                    formal: false,
                    verb: kind == NamespaceKind::Verb,
                    target: None,
                },
                AllocationKind::Field { owner, name, .. } => {
                    fields.entry((owner, name)).or_insert(index as u32);
                    OrderEvent {
                        kind: EventKind::Field,
                        owner,
                        name,
                        formal: false,
                        verb: false,
                        target: None,
                    }
                }
                AllocationKind::Procedure {
                    owner,
                    formal,
                    verb,
                    name,
                    ..
                } => {
                    procedures
                        .entry((owner, name, verb))
                        .or_default()
                        .push(index as u32);
                    OrderEvent {
                        kind: EventKind::Procedure,
                        owner,
                        name,
                        formal,
                        verb,
                        target: None,
                    }
                }
                AllocationKind::Parent { owner, value } => OrderEvent {
                    kind: EventKind::Parent,
                    owner,
                    name: none,
                    formal: false,
                    verb: false,
                    target: expanded_source
                        .get(value.start..value.end)
                        .and_then(|text| dm_syntax::parse_expression(text).expr)
                        .and_then(|expr| match expr.kind {
                            ExprKind::TypePath(path) => Some(SymbolId::of(&path)),
                            _ => None,
                        }),
                },
            };
            hash.update(&[order.kind as u8, order.formal as u8, order.verb as u8]);
            hash.update(&order.owner.bits().to_le_bytes());
            hash.update(&order.name.bits().to_le_bytes());
            hash.update(&order.target.map_or(0, |target| target.bits()).to_le_bytes());
            events.push(order);
        }
        Self {
            events,
            digest: hash.digest128(),
            procedures,
            fields,
        }
    }
    /// The ledger event of a procedure body: the `occurrence`th definition of the name in its owner.
    pub(crate) fn procedure(
        &self,
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
        occurrence: u32,
    ) -> Option<u32> {
        self.procedures
            .get(&(owner, name, verb))
            .and_then(|events| events.get(occurrence as usize))
            .copied()
    }
    /// The first field event of a variable in its owner.
    pub(crate) fn field(&self, owner: SymbolId, name: SymbolId) -> Option<u32> {
        self.fields.get(&(owner, name)).copied()
    }
}

/// What an initializer expression needs, and whether it names `world`.
#[derive(Default)]
pub(crate) struct Facts {
    pub refs: Vec<Ref>,
    pub world: bool,
}

pub(crate) fn expression_facts(source: &str, owner: SymbolId) -> Option<Facts> {
    let parsed = dm_syntax::parse_expression(source);
    if !parsed.diagnostics.is_empty() {
        return None;
    }
    let mut facts = Facts::default();
    walk(&parsed.expr?, owner, &mut facts);
    Some(facts)
}

/// The declared type of a variable that has an initializer is one more reference of that initializer. A typed list
/// asks for its element type; an untyped or plain `list` asks for none.
pub(crate) fn declared_type_ref(declared: Option<&str>) -> Option<Ref> {
    let declared = declared?;
    let rest = declared
        .strip_prefix("/list")
        .filter(|rest| rest.is_empty() || rest.starts_with('/'));
    match rest {
        Some("") => None,
        Some(element) => Some(Ref::Type(SymbolId::of(element))),
        None => Some(Ref::Type(SymbolId::of(declared))),
    }
}

fn walk(expr: &Expr, owner: SymbolId, out: &mut Facts) {
    match &expr.kind {
        ExprKind::Ident(name) => {
            if name == "world" {
                out.world = true;
            } else {
                out.refs.push(Ref::Ident(SymbolId::of(name)));
            }
        }
        ExprKind::Literal(_) => {}
        ExprKind::TypePath(path) => type_path(path, owner, out),
        ExprKind::Unary { value, .. } => walk(value, owner, out),
        ExprKind::Binary { lhs, rhs, .. } => {
            walk(lhs, owner, out);
            walk(rhs, owner, out);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            walk(condition, owner, out);
            walk(then_value, owner, out);
            walk(else_value, owner, out);
        }
        ExprKind::Call { callee, args } => {
            // A name before `=` in the arguments of a call names the parameter, except in the constructors of a
            // list, where it is a key.
            let mut keyed = false;
            match &callee.kind {
                ExprKind::Ident(name) => {
                    keyed = matches!(name.as_str(), "list" | "alist");
                    if name != "new" {
                        out.refs.push(Ref::Call(SymbolId::of(name)));
                    }
                }
                _ => walk(callee, owner, out),
            }
            for argument in args {
                match &argument.kind {
                    ExprKind::Binary { op, lhs, rhs }
                        if op == "=" && !keyed && matches!(lhs.kind, ExprKind::Ident(_)) =>
                    {
                        walk(rhs, owner, out)
                    }
                    _ => walk(argument, owner, out),
                }
            }
        }
        ExprKind::Member { object, .. } | ExprKind::SafeMember { object, .. } => {
            walk(object, owner, out)
        }
        ExprKind::StaticMember { object, .. } => match &object.kind {
            // `type::name` names the type the initializer is declared in.
            ExprKind::Ident(name) if name == "type" => out.refs.push(Ref::Type(owner)),
            _ => walk(object, owner, out),
        },
        ExprKind::TypeFilter { value, types } => {
            walk(value, owner, out);
            for path in types {
                type_path(path, owner, out);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            walk(object, owner, out);
            for (_, value) in fields {
                walk(value, owner, out);
            }
        }
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            walk(object, owner, out);
            walk(index, owner, out);
        }
        ExprKind::Group(inner) => walk(inner, owner, out),
    }
}

fn type_path(path: &str, owner: SymbolId, out: &mut Facts) {
    // `.proc/name` is a procedure of the owner; `/type.proc/name` one of that type (and names the type); a path with
    // a `/proc/` or `/verb/` segment names the procedure only.
    if let Some(name) = path
        .strip_prefix(".proc/")
        .or_else(|| path.strip_prefix(".verb/"))
    {
        out.refs.push(Ref::Procedure {
            owner,
            name: SymbolId::of(name),
        });
        return;
    }
    for marker in [".proc/", ".verb/"] {
        if let Some((prefix, name)) = path.split_once(marker) {
            out.refs.push(Ref::Type(SymbolId::of(prefix)));
            out.refs.push(Ref::Procedure {
                owner: SymbolId::of(prefix),
                name: SymbolId::of(name),
            });
            return;
        }
    }
    for marker in ["/proc/", "/verb/"] {
        if let Some(at) = path.rfind(marker) {
            let prefix = &path[..at];
            out.refs.push(Ref::Procedure {
                owner: SymbolId::of(if prefix.is_empty() { "/" } else { prefix }),
                name: SymbolId::of(&path[at + marker.len()..]),
            });
            return;
        }
    }
    out.refs
        .push(Ref::Type(SymbolId::of(path.trim_end_matches('/'))));
}
