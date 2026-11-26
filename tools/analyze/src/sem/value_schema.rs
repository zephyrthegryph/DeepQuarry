//! Value schemas: `SCHEMA(T, V, schema_path(base))` and its siblings, read from the declaration markers
//! (doc/rewrite/proposals/typed_values.md section 5).
//!
//! DM cannot type a var that holds a path, a refusal reason, a text or a number, so such a var is written `var/x`. The ref lints read an untyped
//! var as "may hold an entity". A `SCHEMA` declaration is the author's statement that the var holds a value of one kind, and the lints
//! believe it (the runtime `schema_check` and `dq_typed_values_defaults_fit` back it): the var is a value, never an entity. A schema is found
//! down the owner's parent chain, as `schema_of` does at run time. A `schema_ref(...)`, `list_of(...)`, `map_of(...)` or `row(...)` schema holds
//! entities (or a container of them) and is not a value schema here.

use std::collections::HashMap;

use crate::sem::decls::Decls;
use crate::sem::Sem;

/// What a value-schema var holds.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ValueKind {
    /// `schema_path(base)`: a type path under `base` (empty: any path).
    Path(String),
    /// `schema_msg()`: null, a `/datum/msg` path, or a `msg_text()` list.
    Msg,
    /// `bool()`, `int()`, `num()`, `enum()`, `flags()`, `schema_text()`: a plain value.
    Plain,
    /// `schema_any()`: any value, entities included (a hook's reply, a config entry's value). The lints accept a call's result in it and still
    /// report an atom or datum assigned to it.
    Any,
    /// `list_of(v)` / `map_of(k, v)` whose members are values: a container of values, never of entities.
    Many,
}

/// The schema expression's kind, or None for one that holds entities or containers (and for text that is no schema call).
pub fn kind_of(expr: &str) -> Option<ValueKind> {
    let e = expr.trim();
    let open = e.find('(')?;
    let name = e[..open].trim();
    match name {
        "schema_path" => {
            let inner = &e[open + 1..];
            let first = crate::sem::decls::split_args(inner.strip_suffix(')').unwrap_or(inner)).into_iter().next().unwrap_or_default();
            Some(ValueKind::Path(first.trim().to_string()))
        }
        "schema_msg" => Some(ValueKind::Msg),
        "schema_any" => Some(ValueKind::Any),
        "bool" | "int" | "num" | "enum" | "flags" | "schema_text" => Some(ValueKind::Plain),
        "list_of" | "map_of" => {
            let inner = &e[open + 1..];
            let args = crate::sem::decls::split_args(inner.strip_suffix(')').unwrap_or(inner));
            // The member schema is the last schema argument (`map_of(key, value)`); a named option follows it.
            let member = args.iter().rev().find(|a| !is_named(a))?;
            kind_of(member).map(|_| ValueKind::Many)
        }
        _ => None,
    }
}

/// A `name = value` option argument (not a schema).
fn is_named(arg: &str) -> bool {
    let t = arg.trim_start();
    let ident = t.chars().take_while(|c| c.is_alphanumeric() || *c == '_').count();
    ident > 0 && t[ident..].trim_start().starts_with('=') && !t[ident..].trim_start().starts_with("==")
}

#[derive(Default)]
pub struct ValueSchemas {
    by_type: HashMap<String, HashMap<String, ValueKind>>,
}

impl ValueSchemas {
    pub fn build(decls: &Decls) -> ValueSchemas {
        let mut v = ValueSchemas::default();
        for name in ["SCHEMA", "TRACKED_SCHEMA"] {
            for m in decls.markers_named(name) {
                let (Some(t), Some(var), Some(expr)) = (m.args.first(), m.args.get(1), m.args.get(2)) else { continue };
                if let Some(k) = kind_of(expr) {
                    v.by_type.entry(t.trim().to_string()).or_default().insert(var.trim().to_string(), k);
                }
            }
        }
        v
    }

    pub fn is_empty(&self) -> bool {
        self.by_type.is_empty()
    }

    /// The value schema declared on exactly `ty`.
    pub fn declared_on(&self, ty: &str, var: &str) -> Option<&ValueKind> {
        self.by_type.get(ty).and_then(|m| m.get(var))
    }

    /// The value schema of `ty`'s var, found on the type or the nearest ancestor that declares one.
    pub fn find(&self, sem: &Sem, ty: &str, var: &str) -> Option<&ValueKind> {
        let mut cur = Some(ty.to_string());
        let mut guard = 0;
        while let Some(t) = cur {
            if let Some(k) = self.by_type.get(&t).and_then(|m| m.get(var)) {
                return Some(k);
            }
            guard += 1;
            if guard > 64 {
                break;
            }
            cur = sem.parent_of(&t).filter(|p| p != &t);
        }
        None
    }

    /// Whether the path literal `lit` is a legal value of the kind. A kind that is not a path accepts none.
    pub fn accepts_path(&self, sem: &Sem, kind: &ValueKind, lit: &str) -> bool {
        match kind {
            ValueKind::Path(base) => base.is_empty() || sem.is_subtype(lit, base),
            ValueKind::Msg => sem.is_subtype(lit, "/datum/msg"),
            ValueKind::Plain => false,
            ValueKind::Many | ValueKind::Any => true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kinds() {
        assert_eq!(kind_of("schema_path(/obj/item/stack)"), Some(ValueKind::Path("/obj/item/stack".into())));
        assert_eq!(kind_of("schema_path(/obj/item/fish, /obj/item/fish/koi)"), Some(ValueKind::Path("/obj/item/fish".into())));
        assert_eq!(kind_of(" schema_msg() "), Some(ValueKind::Msg));
        assert_eq!(kind_of("schema_any()"), Some(ValueKind::Any));
        assert_eq!(kind_of("schema_text(40)"), Some(ValueKind::Plain));
        assert_eq!(kind_of("int(0, 5)"), Some(ValueKind::Plain));
        assert_eq!(kind_of("schema_ref(/obj)"), None);
        assert_eq!(kind_of("list_of(schema_path(/obj))"), Some(ValueKind::Many));
        assert_eq!(kind_of("map_of(schema_text(), int())"), Some(ValueKind::Many));
        assert_eq!(kind_of("list_of(schema_ref(/obj))"), None);
    }
}
