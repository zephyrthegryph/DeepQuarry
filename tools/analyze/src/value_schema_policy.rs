//! Original value-schema kind policy plus a compact hint-presence projection.
//! This does not claim runtime schema resolution or declaration-kind ordering.
use std::collections::HashSet;
use crate::{raw_marker_policy::{statement_marker,split_args},tree::SourceFile};
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
            let first = crate::raw_marker_policy::split_args(inner.strip_suffix(')').unwrap_or(inner)).into_iter().next().unwrap_or_default();
            Some(ValueKind::Path(first.trim().to_string()))
        }
        "schema_msg" => Some(ValueKind::Msg),
        "schema_any" => Some(ValueKind::Any),
        "bool" | "int" | "num" | "enum" | "flags" | "schema_text" => Some(ValueKind::Plain),
        "list_of" | "map_of" => {
            let inner = &e[open + 1..];
            let args = crate::raw_marker_policy::split_args(inner.strip_suffix(')').unwrap_or(inner));
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
pub struct SchemaHints{recognized:HashSet<(String,String)>}
impl SchemaHints{
    pub fn read(&mut self,file:&SourceFile){
        let text=file.marker().as_str();let mut offset=0;
        for line in text.split('\n'){
            if let Some(marker)=statement_marker(text,offset,line,&["SCHEMA","TRACKED_SCHEMA"]){
                let args=split_args(&text[marker.open+1..marker.close]);
                if let[owner,var,expression,..]=args.as_slice(){if kind_of(expression).is_some(){self.recognized.insert((owner.trim().to_string(),var.trim().to_string()));}}
            }
            offset+=line.len()+1;
        }
    }
    pub fn has(&self,owner:&str,var:&str)->bool{self.recognized.contains(&(owner.to_string(),var.to_string()))}
    pub fn visit_storage(&self,visit:impl FnOnce(&HashSet<(String,String)>)){visit(&self.recognized)}
}
pub fn hint_message(ident:&str)->String{format!("{} carries a value schema: move it to the trait field or sparse slot that schema types",ident)}
