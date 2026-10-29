//! Raw declaration policy for markers intentionally erased by preprocessing.
//! This uses the native lexer, not another DM parser or semantic tree. Callers
//! supply the captured raw workspace sources (including noncompiled markers).
use dm_ir::SymbolId;
use dm_syntax::TokenKind as T;
use dm_tree::SemanticTree;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Kind {
    Path(String),
    Msg,
    Plain,
    Many,
    Any,
}
#[derive(Default)]
pub struct Schemas {
    values: BTreeMap<(SymbolId, SymbolId), Kind>,
}

fn split_args(source: &str) -> Result<Vec<String>, String> {
    let lexed = dm_syntax::lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err("unsupported schema-marker tokens".into());
    }
    let mut depth = 0;
    let mut start = 0;
    let mut out = Vec::new();
    for token in lexed.tokens {
        match token.text(source) {
            "(" | "[" | "{" if token.kind == T::Punctuation => depth += 1,
            ")" | "]" | "}" if token.kind == T::Punctuation => depth -= 1,
            "," if token.kind == T::Punctuation && depth == 0 => {
                out.push(source[start..token.span.start].trim().into());
                start = token.span.end;
            }
            _ => (),
        }
    }
    out.push(source[start..].trim().into());
    Ok(out)
}
pub fn kind_of(expression: &str) -> Option<Kind> {
    let (name, rest) = expression.trim().split_once('(')?;
    let args = split_args(rest.strip_suffix(')')?).ok()?;
    match name.trim() {
        "schema_path" => Some(Kind::Path(args.first()?.trim().into())),
        "schema_msg" => Some(Kind::Msg),
        "schema_any" => Some(Kind::Any),
        "bool" | "int" | "num" | "enum" | "flags" | "schema_text" => Some(Kind::Plain),
        "list_of" | "map_of" => args
            .iter()
            .rev()
            .find(|arg| {
                let prefix: String = arg
                    .chars()
                    .take_while(|ch| ch.is_alphanumeric() || *ch == '_')
                    .collect();
                prefix.is_empty()
                    || !arg[prefix.len()..].trim_start().starts_with('=')
                    || arg[prefix.len()..].trim_start().starts_with("==")
            })
            .and_then(|arg| kind_of(arg))
            .map(|_| Kind::Many),
        _ => None,
    }
}
impl Schemas {
    /// Existing policy lexer/classifier may supply its interpreted schema kind.
    /// This proves neither raw capture authority nor workspace completeness.
    pub fn insert_policy_kind(&mut self, owner: SymbolId, name: SymbolId, kind: Kind) {
        self.values.insert((owner, name), kind);
    }
    /// Borrow unique raw-marker policy storage for host memory accounting.
    pub fn visit_storage(&self, visit: impl FnOnce(&BTreeMap<(SymbolId, SymbolId), Kind>)) {
        visit(&self.values);
    }
    pub fn read_source(&mut self, source: &str) -> Result<(), String> {
        if !source.contains("SCHEMA") {
            return Ok(());
        }
        let lexed = dm_syntax::lex_spans(source);
        // Preserve source positions while removing comments, like the existing
        // raw declaration scanner. Strings remain lexer-owned tokens.
        let mut masked = source.as_bytes().to_vec();
        for token in &lexed.tokens {
            if token.kind == T::Comment {
                for byte in &mut masked[token.span.range()] {
                    if *byte != b'\n' && *byte != b'\r' {
                        *byte = b' ';
                    }
                }
            }
        }
        let masked = String::from_utf8(masked).map_err(|e| e.to_string())?;
        let tokens = &lexed.tokens;
        for (i, token) in tokens.iter().enumerate() {
            if token.kind != T::Ident || !matches!(token.text(source), "SCHEMA" | "TRACKED_SCHEMA")
            {
                continue;
            }
            let line_start = masked[..token.span.start]
                .rfind('\n')
                .map_or(0, |offset| offset + 1);
            if !masked[line_start..token.span.start].trim().is_empty() {
                continue;
            }
            let Some(open) = tokens[i + 1..]
                .iter()
                .position(|t| !matches!(t.kind, T::Whitespace | T::Newline | T::Comment))
                .map(|offset| i + 1 + offset)
            else {
                return Err("schema marker has no arguments".into());
            };
            if tokens[open].text(source) != "(" {
                continue;
            }
            let mut depth = 1;
            let mut close = None;
            for token in &tokens[open + 1..] {
                if token.kind != T::Punctuation {
                    continue;
                }
                match token.text(source) {
                    "(" => depth += 1,
                    ")" => {
                        depth -= 1;
                        if depth == 0 {
                            close = Some(token.span.start);
                            break;
                        }
                    }
                    _ => (),
                }
            }
            let close = close.ok_or("unclosed schema marker")?;
            let args = split_args(&masked[tokens[open].span.end..close])?;
            if let [owner, variable, expression, ..] = args.as_slice() {
                if let Some(kind) = kind_of(expression) {
                    self.values.insert(
                        (SymbolId::of(owner.trim()), SymbolId::of(variable.trim())),
                        kind,
                    );
                }
            }
        }
        Ok(())
    }
    pub fn find<'a>(
        &'a self,
        tree: &SemanticTree,
        owner: SymbolId,
        name: SymbolId,
    ) -> Option<&'a Kind> {
        let mut current = tree.lookup_type(owner);
        let mut depth = 0;
        while let Some(id) = current {
            if let Some(kind) = self.values.get(&(tree.type_node(id)?.path, name)) {
                return Some(kind);
            }
            depth += 1;
            if depth > 64 {
                break;
            } // Reference policy's guard, not an inferred hierarchy limit.
            current = tree.parent(id);
        }
        None
    }
    pub fn accepts_path(tree: &SemanticTree, kind: &Kind, path: &str) -> bool {
        let base = match kind {
            Kind::Path(base) if base.is_empty() => return true,
            Kind::Path(base) => base.as_str(),
            Kind::Msg => "/datum/msg",
            Kind::Plain => return false,
            Kind::Any | Kind::Many => return true,
        };
        let mut current = tree.lookup_type(SymbolId::of(path));
        while let Some(id) = current {
            if tree.type_node(id).unwrap().path == SymbolId::of(base) {
                return true;
            }
            current = tree.parent(id);
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_marker_lexer_ignores_comments_strings_and_definitions() {
        let mut schemas = Schemas::default();
        schemas
            .read_source(
                r#"
#define SCHEMA(T, V, K)
// SCHEMA(/datum/ignored, x, schema_any())
var/text = "SCHEMA(/datum/ignored, x, schema_any())"
SCHEMA(/* class */ /datum/x, path, schema_path(/datum/base))
TRACKED_SCHEMA(/datum/x, loose, schema_any())
SCHEMA(/datum/x, collection, list_of(schema_path(/datum/base), nullable = TRUE))
"#,
            )
            .unwrap();
        assert_eq!(schemas.values.len(), 3);
        assert_eq!(
            schemas.values[&(SymbolId::of("/datum/x"), SymbolId::of("path"))],
            Kind::Path("/datum/base".into())
        );
        assert_eq!(
            schemas.values[&(SymbolId::of("/datum/x"), SymbolId::of("collection"))],
            Kind::Many
        );
    }
    #[test]
    fn malformed_schema_arguments_are_not_clean_results() {
        assert!(Schemas::default()
            .read_source("SCHEMA(/datum/x, value, schema_path(/datum/base)")
            .is_err());
        assert_eq!(
            kind_of("map_of(schema_text(), schema_path(/datum/x))"),
            Some(Kind::Many)
        );
    }
}
