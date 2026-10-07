//! Parsing of the shared declaration model; data structures live in dm-ir.
use dm_ir::{
    ExpressionToken, Parameter, ProcedureSetting, ProcedureSignature, SettingOperation, SymbolId,
    SymbolTable, SymbolicExpression,
};
use dm_syntax::{Span, TokenKind};
fn intern(symbols: &mut SymbolTable, text: &str) -> Result<SymbolId, String> {
    symbols.intern(text).map_err(|error| error.to_string())
}
pub(crate) fn expression(
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<SymbolicExpression, String> {
    let lexed = dm_syntax::lex(text);
    if !lexed.diagnostics.is_empty() {
        return Err("invalid expression tokens in procedure declaration".into());
    }
    let mut tokens = Vec::new();
    for token in lexed.tokens {
        if matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
        ) {
            continue;
        }
        tokens.push(ExpressionToken {
            kind: token.kind,
            text: intern(symbols, &token.text)?,
            relative_span: token.span,
        });
    }
    if tokens.is_empty() {
        return Err("empty procedure declaration expression".into());
    }
    Ok(SymbolicExpression {
        tokens: tokens.into(),
    })
}
fn top_level_tokens(text: &str) -> Vec<(String, Span)> {
    let mut depth = 0;
    let mut result = Vec::new();
    for token in dm_syntax::lex(text).tokens {
        match token.text.as_str() {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => depth -= 1,
            _ => {
                if depth == 0 {
                    result.push((token.text, token.span))
                }
            }
        }
    }
    result
}
fn parameter(text: &str, start: usize, symbols: &mut SymbolTable) -> Result<Parameter, String> {
    let top = top_level_tokens(text);
    let equal = dm_syntax::top_level_assignment_index(text);
    let annotation = top
        .iter()
        .find(|(token, _)| token == "as")
        .map(|(_, span)| *span);
    let source = top
        .iter()
        .find(|(token, _)| token == "in")
        .map(|(_, span)| *span);
    let positions = [
        equal,
        annotation.map(|span| span.start),
        source.map(|span| span.start),
    ];
    let name_end = positions
        .iter()
        .flatten()
        .copied()
        .min()
        .unwrap_or(text.len());
    let declaration = text[..name_end].trim().trim_start_matches("var/");
    let parts: Vec<_> = declaration.trim_matches('/').split('/').collect();
    let name = parts.last().copied().unwrap_or("");
    let name = name.split('[').next().unwrap().trim();
    if name.is_empty() {
        return Err("procedure argument has no name".into());
    }
    let declared_type = if parts.len() > 1 {
        Some(intern(
            symbols,
            &format!("/{}", parts[..parts.len() - 1].join("/")),
        )?)
    } else {
        None
    };
    fn end(positions: &[Option<usize>], start: usize, len: usize) -> usize {
        positions
            .iter()
            .flatten()
            .copied()
            .filter(|position| *position > start)
            .min()
            .unwrap_or(len)
    }
    let default = equal
        .map(|index| {
            expression(
                text[index + 1..end(&positions, index, text.len())].trim(),
                symbols,
            )
        })
        .transpose()?;
    let input_annotation = annotation
        .map(|span| {
            expression(
                text[span.end..end(&positions, span.start, text.len())].trim(),
                symbols,
            )
        })
        .transpose()?;
    let source_expression = source
        .map(|span| {
            expression(
                text[span.end..end(&positions, span.start, text.len())].trim(),
                symbols,
            )
        })
        .transpose()?;
    Ok(Parameter {
        name: intern(symbols, name)?,
        declared_type,
        default,
        input_annotation,
        source_expression,
        relative_span: Span::new(start, start + text.len()),
    })
}
pub(crate) fn parse_signature(
    arguments: &str,
    trailing: &str,
    symbols: &mut SymbolTable,
) -> Result<ProcedureSignature, String> {
    let mut parameters = Vec::new();
    let mut variadic = false;
    let mut start = 0;
    let mut stops: Vec<_> = top_level_tokens(arguments)
        .into_iter()
        .filter(|(token, _)| token == ",")
        .map(|(_, span)| span.start)
        .collect();
    stops.push(arguments.len());
    for stop in stops {
        let untrimmed = &arguments[start..stop];
        let leading = untrimmed.len() - untrimmed.trim_start().len();
        let text = untrimmed.trim();
        if text == "..." {
            variadic = true
        } else if !text.is_empty() {
            if variadic {
                return Err("procedure argument follows variadic marker".into());
            }
            parameters.push(parameter(text, start + leading, symbols)?);
        }
        start = stop + 1;
    }
    let trailing = trailing.trim();
    let return_annotation = if trailing.is_empty() {
        None
    } else {
        Some(expression(
            trailing
                .strip_prefix("as ")
                .ok_or("unsupported procedure return annotation")?,
            symbols,
        )?)
    };
    Ok(ProcedureSignature {
        parameters: parameters.into(),
        variadic,
        return_annotation,
    })
}
pub(crate) fn parse_setting(
    text: &str,
    symbols: &mut SymbolTable,
) -> Result<ProcedureSetting, String> {
    let text = text
        .trim()
        .strip_prefix("set ")
        .ok_or("expected set declaration")?;
    let (name, operation, value) = if let Some(index) = dm_syntax::top_level_assignment_index(text)
    {
        (
            text[..index].trim(),
            SettingOperation::Assign,
            text[index + 1..].trim(),
        )
    } else {
        let span = top_level_tokens(text)
            .into_iter()
            .find(|(token, _)| token == "in")
            .map(|(_, span)| span)
            .ok_or("set declaration missing assignment or in")?;
        (
            text[..span.start].trim(),
            SettingOperation::In,
            text[span.end..].trim(),
        )
    };
    if !matches!(
        name,
        "name"
            | "desc"
            | "category"
            | "src"
            | "invisibility"
            | "waitfor"
            | "hidden"
            | "background"
            | "instant"
            | "popup_menu"
    ) {
        return Err(format!("unknown procedure setting: {name}"));
    }
    Ok(ProcedureSetting {
        name: intern(symbols, name)?,
        operation,
        value: expression(value, symbols)?,
    })
}

pub(crate) fn parse_array(
    declaration: &str,
    element_type: Option<SymbolId>,
    symbols: &mut SymbolTable,
) -> Result<Option<std::sync::Arc<dm_ir::ArrayDeclaration>>, String> {
    let tokens = dm_syntax::lex(declaration);
    let mut depth = 0;
    let mut start = None;
    let mut dimensions = Vec::new();
    for token in tokens.tokens {
        match token.text.as_str() {
            "[" => {
                if depth == 0 {
                    start = Some(token.span.end)
                }
                depth += 1
            }
            "]" => {
                if depth == 0 {
                    return Err("unmatched array declaration bracket".into());
                }
                depth -= 1;
                if depth == 0 {
                    let text = declaration[start.take().unwrap()..token.span.start].trim();
                    dimensions.push(if text.is_empty() {
                        None
                    } else {
                        Some(expression(text, symbols)?)
                    });
                }
            }
            _ => {}
        }
    }
    if depth != 0 {
        return Err("unterminated array declaration".into());
    }
    if dimensions.is_empty() {
        Ok(None)
    } else {
        Ok(Some(std::sync::Arc::new(dm_ir::ArrayDeclaration {
            dimensions: dimensions.into(),
            element_type,
        })))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn typed_default_input_and_source_are_separate() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "value as text, count = 3 as num, target as obj in view(1)",
            "",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(signature.parameters.len(), 3);
        let count = &signature.parameters[1];
        assert_eq!(symbols.text(count.name), Some("count"));
        assert_eq!(
            symbols.text(count.default.as_ref().unwrap().tokens[0].text),
            Some("3")
        );
        assert_eq!(
            symbols.text(count.input_annotation.as_ref().unwrap().tokens[0].text),
            Some("num")
        );
        assert!(count.source_expression.is_none());
        assert!(signature.parameters[2].source_expression.is_some());
    }
    #[test]
    fn nested_defaults_and_variadic_are_not_split_as_arguments() {
        let mut symbols = SymbolTable::default();
        let signature = parse_signature(
            "list/items = list(1, list(2,3)), ...",
            " as /datum/result",
            &mut symbols,
        )
        .unwrap();
        assert_eq!(signature.parameters.len(), 1);
        assert_eq!(
            signature.parameters[0].declared_type,
            Some(SymbolId::of("/list"))
        );
        assert!(signature.variadic);
        assert!(signature.return_annotation.is_some());
    }
    #[test]
    fn source_setting_is_typed_without_guessing_wire_flags() {
        let mut symbols = SymbolTable::default();
        let setting = parse_setting("set src in world", &mut symbols).unwrap();
        assert_eq!(setting.operation, SettingOperation::In);
        assert_eq!(symbols.text(setting.name), Some("src"));
        assert_eq!(symbols.text(setting.value.tokens[0].text), Some("world"));
        assert!(parse_setting("set imaginary = 1", &mut symbols).is_err());
    }
    #[test]
    fn operator_adjacency_is_semantic_not_ordinary_position() {
        let mut symbols = SymbolTable::default();
        let joined = expression("seed++", &mut symbols).unwrap();
        let separated = expression("seed + +", &mut symbols).unwrap();
        assert_ne!(joined.fingerprint(), separated.fingerprint());
        assert_eq!(joined.source_text(&symbols).as_deref(), Some("seed++"));
        assert_eq!(separated.source_text(&symbols).as_deref(), Some("seed + +"));
    }
    #[test]
    fn expression_fingerprint_excludes_relative_whitespace_positions() {
        let mut symbols = SymbolTable::default();
        let compact = expression("seed+1", &mut symbols).unwrap();
        let spaced = expression("seed + 1", &mut symbols).unwrap();
        assert_eq!(compact.fingerprint(), spaced.fingerprint());
        assert_ne!(
            compact.tokens[1].relative_span,
            spaced.tokens[1].relative_span
        );
    }
}
