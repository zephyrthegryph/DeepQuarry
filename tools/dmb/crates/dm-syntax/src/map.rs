//! Ordered symbolic DMM syntax. No semantic lookup or output IDs are assigned.
use crate::{Span, SpanToken, TokenKind};
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MapTemplate<'a> {
    pub key: &'a str,
    pub payload: &'a str,
    pub key_span: Span,
    pub payload_span: Span,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MapBlock<'a> {
    pub axes: [usize; 3],
    pub cells: &'a str,
    pub cells_span: Span,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum MapRecord {
    Template(usize),
    Block(usize),
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MapSyntax<'a> {
    pub templates: Vec<MapTemplate<'a>>,
    pub blocks: Vec<MapBlock<'a>>,
    /// Joint occurrence order, including interleaved template/block sections.
    pub records: Vec<MapRecord>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MapError {
    pub span: Span,
    pub message: String,
}
fn span(source: &str, part: &str) -> Span {
    let start = part.as_ptr() as usize - source.as_ptr() as usize;
    Span::new(start, start + part.len())
}
/// Lex once, retain declaration order in each map grammar section and exact
/// borrowed payload bytes. Semantic cell decoding/width validation is separate.
pub fn parse_map(source: &str) -> Result<MapSyntax<'_>, MapError> {
    let lexed = crate::lex_spans(source);
    if let Some(error) = lexed.diagnostics.first() {
        return Err(MapError {
            span: error.span,
            message: error.message.clone(),
        });
    }
    let tokens: Vec<SpanToken> = lexed
        .tokens
        .into_iter()
        .filter(|t| {
            !matches!(
                t.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect();
    let error = |message| MapError {
        span: Span::new(0, source.len()),
        message,
    };
    let templates: Vec<_> = templates_from_tokens(source, &tokens)
        .map_err(error)?
        .into_iter()
        .map(|(key, payload)| MapTemplate {
            key,
            payload,
            key_span: span(source, key),
            payload_span: span(source, payload),
        })
        .collect();
    let blocks: Vec<_> = blocks_from_tokens(source, &tokens)
        .map_err(error)?
        .into_iter()
        .map(|(axes, cells)| MapBlock {
            axes,
            cells,
            cells_span: span(source, cells),
        })
        .collect();
    let mut ordered: Vec<_> = templates
        .iter()
        .enumerate()
        .map(|(index, record)| (record.key_span.start, MapRecord::Template(index)))
        .chain(
            blocks
                .iter()
                .enumerate()
                .map(|(index, record)| (record.cells_span.start, MapRecord::Block(index))),
        )
        .collect();
    ordered.sort_by_key(|(start, _)| *start);
    Ok(MapSyntax {
        templates,
        blocks,
        records: ordered.into_iter().map(|(_, record)| record).collect(),
    })
}
pub fn map_blocks(source: &str) -> Result<Vec<([usize; 3], &str)>, String> {
    let lexed = crate::lex_spans(source);
    if !lexed.diagnostics.is_empty() {
        return Err("invalid map tokens".into());
    }
    let tokens = lexed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                crate::TokenKind::Whitespace
                    | crate::TokenKind::Newline
                    | crate::TokenKind::Comment
            )
        })
        .collect::<Vec<_>>();
    blocks_from_tokens(source, &tokens)
}

fn blocks_from_tokens<'a>(
    source: &'a str,
    tokens: &[crate::SpanToken],
) -> Result<Vec<([usize; 3], &'a str)>, String> {
    let mut blocks = Vec::new();
    for window in tokens.windows(9) {
        if [0, 2, 4, 6, 7]
            .into_iter()
            .zip(["(", ",", ",", ")", "="])
            .any(|(index, text)| window[index].text(source) != text)
        {
            continue;
        }
        if window[8].kind != crate::TokenKind::String {
            continue;
        }
        let raw = window[8].text(source);
        let Some(text) = raw
            .strip_prefix("{\"")
            .and_then(|text| text.strip_suffix("\"}"))
        else {
            continue;
        };
        let mut axes = [0; 3];
        for (axis, index) in [1, 3, 5].into_iter().enumerate() {
            axes[axis] = window[index]
                .text(source)
                .parse()
                .map_err(|_| "invalid map coordinates")?;
        }
        if axes.contains(&0) {
            return Err("invalid map coordinates".into());
        }
        blocks.push((axes, text));
    }
    Ok(blocks)
}

pub fn map_templates(source: &str) -> Result<Vec<(&str, &str)>, String> {
    let lexed = crate::lex_spans(source);
    if let Some(error) = lexed.diagnostics.first() {
        return Err(error.message.clone());
    }
    let tokens: Vec<_> = lexed
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                crate::TokenKind::Whitespace
                    | crate::TokenKind::Newline
                    | crate::TokenKind::Comment
            )
        })
        .collect();
    templates_from_tokens(source, &tokens)
}

fn templates_from_tokens<'a>(
    source: &'a str,
    tokens: &[crate::SpanToken],
) -> Result<Vec<(&'a str, &'a str)>, String> {
    let mut result = Vec::new();
    let mut at = 0;
    while at + 2 < tokens.len() {
        let key = &tokens[at];
        if key.kind != crate::TokenKind::String
            || tokens[at + 1].text(source) != "="
            || tokens[at + 2].text(source) != "("
        {
            at += 1;
            continue;
        }
        let start = tokens[at + 2].span.end;
        let mut end = at + 3;
        let mut depth = 1usize;
        while end < tokens.len() {
            match tokens[end].text(source) {
                "(" => depth += 1,
                ")" => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                _ => {}
            }
            end += 1;
        }
        if depth != 0 {
            return Err("unclosed map template".into());
        }
        let key_text = key
            .text(source)
            .strip_prefix('"')
            .and_then(|value| value.strip_suffix('"'))
            .ok_or("invalid map template key")?;
        if key_text.is_empty() {
            return Err("empty map template key".into());
        }
        result.push((key_text, &source[start..tokens[end].span.start]));
        at = end + 1;
    }
    Ok(result)
}

pub fn split_top_level(source: &str, separator: char) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0usize;
    let mut quote = None;
    let mut start = 0;
    let mut escape = false;
    for (at, ch) in source.char_indices() {
        if escape {
            escape = false;
            continue;
        }
        if ch == '\\' && quote.is_some() {
            escape = true;
            continue;
        }
        if let Some(ending) = quote {
            if ch == ending {
                quote = None;
            }
            continue;
        }
        match ch {
            '\'' | '"' => quote = Some(ch),
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => depth = depth.saturating_sub(1),
            _ if ch == separator && depth == 0 => {
                parts.push(&source[start..at]);
                start = at + ch.len_utf8();
            }
            _ => {}
        }
    }
    parts.push(&source[start..]);
    parts
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn borrowed_sections_preserve_order_spans_and_nested_values() {
        let source = "\"z\"=(/obj{v=list(1,2)},/turf,/area)\n\"a\"=(/turf,/area)\n(1,2,3)={\"za\"}";
        let map = parse_map(source).unwrap();
        assert_eq!(
            map.templates.iter().map(|t| t.key).collect::<Vec<_>>(),
            ["z", "a"]
        );
        assert_eq!(map.blocks[0].axes, [1, 2, 3]);
        assert_eq!(&source[map.blocks[0].cells_span.range()], "za");
        assert_eq!(split_top_level(map.templates[0].payload, ',').len(), 3);
    }
    #[test]
    fn existing_single_cell_fixture_is_symbolic() {
        let source = include_str!("../../../fixtures/native_compiler/map_stack_one.dmm");
        let parsed = parse_map(source).unwrap();
        assert_eq!(parsed.templates[0].key, "a");
        assert_eq!(parsed.templates[0].payload, "/turf,/area");
        assert_eq!(parsed.blocks[0].axes, [1, 1, 1]);
        assert_eq!(
            parsed.records,
            [MapRecord::Template(0), MapRecord::Block(0)]
        );
    }
    #[test]
    fn legacy_errors_are_preserved() {
        assert_eq!(
            map_blocks("(0,1,1)={\"a\"}").unwrap_err(),
            "invalid map coordinates"
        );
        assert_eq!(
            map_templates("\"a\"=(/turf").unwrap_err(),
            "unclosed map template"
        );
    }
}
