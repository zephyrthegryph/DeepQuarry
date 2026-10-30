//! Original value-schema kind policy plus a compact hint-presence projection.
//! This does not claim runtime schema resolution or declaration-kind ordering.
use crate::{
    raw_marker_policy::{split_args, statement_marker},
    tree::SourceFile,
};
use std::collections::HashSet;
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
    kind_of_observed(expr, 0, None).expect("unbounded original schema kind policy")
}
/// Captured admission only; legacy callers keep the original unbounded policy.
/// Every recursive temporary is reserved BEFORE split_args clones its input.
struct SchemaBudget<'a> {
    remaining: &'a mut usize,
    checkpoint: &'a mut dyn FnMut() -> Result<(), String>,
}
const MAX_CAPTURED_SCHEMA_DEPTH: usize = 128;
impl SchemaBudget<'_> {
    fn admit(&mut self, depth: usize, bytes: usize) -> Result<(), String> {
        (self.checkpoint)()?;
        if depth > MAX_CAPTURED_SCHEMA_DEPTH {
            return Err("captured schema nesting exceeds bounded policy admission".into());
        }
        let charge = bytes
            .checked_mul(16)
            .and_then(|n| n.checked_add(4096))
            .ok_or("schema recursive temporary accounting overflow")?;
        *self.remaining = self
            .remaining
            .checked_sub(charge)
            .ok_or("schema recursive temporary exceeds admission before allocation")?;
        Ok(())
    }
}
fn kind_of_observed(
    expr: &str,
    depth: usize,
    mut budget: Option<&mut SchemaBudget<'_>>,
) -> Result<Option<ValueKind>, String> {
    if let Some(budget) = budget.as_deref_mut() {
        budget.admit(depth, expr.len())?;
    }
    let e = expr.trim();
    let Some(open) = e.find('(') else {
        return Ok(None);
    };
    let name = e[..open].trim();
    Ok(match name {
        "schema_path" => {
            let inner = &e[open + 1..];
            let first =
                crate::raw_marker_policy::split_args(inner.strip_suffix(')').unwrap_or(inner))
                    .into_iter()
                    .next()
                    .unwrap_or_default();
            Some(ValueKind::Path(first.trim().to_string()))
        }
        "schema_msg" => Some(ValueKind::Msg),
        "schema_any" => Some(ValueKind::Any),
        "bool" | "int" | "num" | "enum" | "flags" | "schema_text" => Some(ValueKind::Plain),
        "list_of" | "map_of" => {
            let inner = &e[open + 1..];
            let args =
                crate::raw_marker_policy::split_args(inner.strip_suffix(')').unwrap_or(inner));
            // Original policy: last non-named schema argument, including its
            // exact existing is_named spelling behavior.
            let member = if budget.is_some() {
                let mut selected = None;
                for arg in args.iter().rev() {
                    // Original is_named counts chars and uses that count as a
                    // byte offset. Do not invoke its unissued Unicode domain
                    // in captured policy (legacy behavior stays unchanged).
                    let prefix = arg
                        .trim_start()
                        .chars()
                        .take_while(|c| c.is_alphanumeric() || *c == '_');
                    if prefix.clone().count() != prefix.map(char::len_utf8).sum::<usize>() {
                        return Err("captured schema Unicode option-name policy is unissued".into());
                    }
                    if !is_named(arg) {
                        selected = Some(arg);
                        break;
                    }
                }
                selected
            } else {
                args.iter().rev().find(|a| !is_named(a))
            };
            let Some(member) = member else {
                return Ok(None);
            };
            kind_of_observed(member, depth + 1, budget)?.map(|_| ValueKind::Many)
        }
        _ => None,
    })
}

/// A `name = value` option argument (not a schema).
fn is_named(arg: &str) -> bool {
    let t = arg.trim_start();
    let ident = t
        .chars()
        .take_while(|c| c.is_alphanumeric() || *c == '_')
        .count();
    ident > 0
        && t[ident..].trim_start().starts_with('=')
        && !t[ident..].trim_start().starts_with("==")
}

#[derive(Default)]
pub struct SchemaHints {
    recognized: HashSet<(String, String)>,
}
impl SchemaHints {
    pub fn read(&mut self, file: &SourceFile) {
        self.read_internal(file, &mut usize::MAX, false, &mut || Ok(()))
            .expect("unbounded original schema-hint collector")
    }
    pub fn read_bounded(&mut self, file: &SourceFile, remaining: &mut usize) -> Result<(), String> {
        self.read_bounded_observed(file, remaining, &mut || Ok(()))
    }
    pub fn read_bounded_observed(
        &mut self,
        file: &SourceFile,
        remaining: &mut usize,
        checkpoint: &mut dyn FnMut() -> Result<(), String>,
    ) -> Result<(), String> {
        self.read_internal(file, remaining, true, checkpoint)
    }
    fn read_internal(
        &mut self,
        file: &SourceFile,
        remaining: &mut usize,
        bounded: bool,
        checkpoint: &mut dyn FnMut() -> Result<(), String>,
    ) -> Result<(), String> {
        let text = file.marker().as_str();
        let mut offset = 0;
        for line in text.split('\n') {
            checkpoint()?;
            if let Some(marker) =
                statement_marker(text, offset, line, &["SCHEMA", "TRACKED_SCHEMA"])
            {
                let temporary = (marker.close - marker.open)
                    .checked_mul(16)
                    .and_then(|n| n.checked_add(4096))
                    .ok_or("schema temporary admission overflow")?;
                let mut room = remaining
                    .checked_sub(temporary)
                    .ok_or("schema hint arguments exceed admission before allocation")?;
                let args = split_args(&text[marker.open + 1..marker.close]);
                if let [owner, var, expression, ..] = args.as_slice() {
                    let recognized = if bounded {
                        kind_of_observed(
                            expression,
                            0,
                            Some(&mut SchemaBudget {
                                remaining: &mut room,
                                checkpoint,
                            }),
                        )?
                    } else {
                        kind_of(expression)
                    };
                    if recognized.is_some() {
                        let charge = owner
                            .len()
                            .checked_add(var.len())
                            .and_then(|n| n.checked_mul(4))
                            .and_then(|n| n.checked_add(256))
                            .ok_or("schema hint retention overflow")?;
                        if charge > room {
                            return Err("schema hint row exceeds admission before retention".into());
                        }
                        *remaining -= charge;
                        self.recognized
                            .insert((owner.trim().to_string(), var.trim().to_string()));
                    }
                }
            }
            offset += line.len() + 1;
        }
        Ok(())
    }
    pub fn has(&self, owner: &str, var: &str) -> bool {
        self.recognized
            .contains(&(owner.to_string(), var.to_string()))
    }
    pub fn visit_storage(&self, visit: impl FnOnce(&HashSet<(String, String)>)) {
        visit(&self.recognized)
    }
}
pub fn hint_message(ident: &str) -> String {
    format!(
        "{} carries a value schema: move it to the trait field or sparse slot that schema types",
        ident
    )
}

#[cfg(all(test, feature = "native-policy"))]
mod captured_admission_tests {
    use super::*;
    #[test]
    fn recursive_schema_temporaries_and_depth_refuse_before_clean_retention() {
        let expression = (0..24).fold("schema_path(/datum)".to_string(), |s, _| {
            format!("list_of({s})")
        });
        let file = SourceFile::from_text(
            "code/schema.dm",
            &format!("SCHEMA(/datum, refs, {expression})\n"),
        );
        let mut hints = SchemaHints::default();
        let mut room = expression.len() * 16 * 3 + 16384;
        let error = hints.read_bounded(&file, &mut room).unwrap_err();
        assert!(error.contains("recursive temporary"), "{error}");
        assert!(!hints.has("/datum", "refs"));
        let deep = (0..MAX_CAPTURED_SCHEMA_DEPTH + 2)
            .fold("schema_msg()".to_string(), |s, _| format!("list_of({s})"));
        let file =
            SourceFile::from_text("code/deep.dm", &format!("SCHEMA(/datum, refs, {deep})\n"));
        let error = hints
            .read_bounded(&file, &mut (64 * 1024 * 1024))
            .unwrap_err();
        assert!(error.contains("nesting"), "{error}");
        assert!(!hints.has("/datum", "refs"));
    }
    #[test]
    fn captured_unicode_named_option_refuses_without_invoking_old_byte_slice() {
        let file = SourceFile::from_text(
            "code/unicode.dm",
            "SCHEMA(/datum, refs, list_of(schema_msg(), \u{e9} = 1))\n",
        );
        let mut hints = SchemaHints::default();
        let error = hints
            .read_bounded(&file, &mut (64 * 1024 * 1024))
            .unwrap_err();
        assert!(error.contains("Unicode option-name"), "{error}");
        assert!(!hints.has("/datum", "refs"));
    }
    #[test]
    fn observed_recursive_policy_keeps_old_kinds_and_actual_cancellation() {
        let file = SourceFile::from_text(
            "code/schema.dm",
            "SCHEMA(/datum, refs, list_of(map_of(schema_text(), schema_path(/datum))))\n",
        );
        let mut bounded = SchemaHints::default();
        let mut plain = SchemaHints::default();
        plain.read(&file);
        bounded
            .read_bounded(&file, &mut (64 * 1024 * 1024))
            .unwrap();
        assert_eq!(plain.recognized, bounded.recognized);
        assert!(bounded.has("/datum", "refs"));
        let mut polls = 0;
        let mut fresh = SchemaHints::default();
        let error = fresh
            .read_bounded_observed(&file, &mut (64 * 1024 * 1024), &mut || {
                polls += 1;
                if polls >= 3 {
                    Err("cancelled recursive schema".into())
                } else {
                    Ok(())
                }
            })
            .unwrap_err();
        assert_eq!(error, "cancelled recursive schema");
        assert!(!fresh.has("/datum", "refs"));
    }
}
