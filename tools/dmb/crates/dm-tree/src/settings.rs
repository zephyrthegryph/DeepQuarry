//! Ordered, unevaluated procedure settings with compact structural context.
use dm_ir::{ProcedureSettingNode, SymbolTable};
use dm_syntax::{Item, Span, TokenKind};
use std::sync::Arc;

fn keyword(header: &str, word: &str) -> bool {
    header.trim_start().strip_prefix(word).is_some_and(|tail| {
        tail.is_empty() || tail.starts_with(char::is_whitespace) || tail.starts_with('(')
    })
}
fn has_setting(item: &Item) -> bool {
    keyword(&item.header, "set") || item.children.iter().any(has_setting)
}
fn chain_end(items: &[Item], start: usize) -> usize {
    let mut end = start + 1;
    while end < items.len() && keyword(&items[end].header, "else") {
        end += 1;
    }
    end
}

/// Remove executable leaves while retaining every setting ancestor. Else is a
/// sibling in the indentation AST: retain its whole chain if any branch has a
/// setting, including empty antecedent branches needed to express negation.
pub fn compact_setting_items(items: Vec<Item>) -> Vec<Item> {
    let mut input = items.into_iter().peekable();
    let mut result = Vec::new();
    while let Some(item) = input.next() {
        if keyword(&item.header, "if") {
            let mut chain = vec![item];
            while input
                .peek()
                .is_some_and(|item| keyword(&item.header, "else"))
            {
                chain.push(input.next().unwrap());
            }
            if chain.iter().any(has_setting) {
                for mut item in chain {
                    item.children = compact_setting_items(item.children);
                    result.push(item);
                }
            }
        } else if has_setting(&item) {
            let mut item = item;
            item.children = compact_setting_items(item.children);
            result.push(item);
        }
    }
    result
}

/// Remove setting leaves only after the caller has verified/evaluated setting
/// metadata. Keep mixed conditional chains whole, including empty antecedents;
/// drop a setting-only chain whose guard has already been resolved as metadata.
/// Other control contexts remain executable rather than being guessed away.
pub fn strip_setting_items(items: Vec<Item>) -> Vec<Item> {
    let mut input = items.into_iter().peekable();
    let mut result = Vec::new();
    while let Some(mut item) = input.next() {
        if keyword(&item.header, "set") {
            continue;
        }
        if keyword(&item.header, "if") {
            let mut chain = vec![item];
            while input
                .peek()
                .is_some_and(|item| keyword(&item.header, "else"))
            {
                chain.push(input.next().unwrap());
            }
            let had_setting = chain.iter().any(has_setting);
            for item in &mut chain {
                item.children = strip_setting_items(std::mem::take(&mut item.children));
            }
            if !had_setting || chain.iter().any(|item| !item.children.is_empty()) {
                result.extend(chain);
            }
        } else {
            item.children = strip_setting_items(item.children);
            result.push(item);
        }
    }
    result
}

fn condition(header: &str, symbols: &mut SymbolTable) -> Result<dm_ir::SymbolicExpression, String> {
    let text = header
        .trim()
        .strip_prefix("if")
        .ok_or("expected conditional setting context")?
        .trim();
    let tokens = dm_syntax::lex_spans(text);
    if !tokens.diagnostics.is_empty() {
        return Err("invalid setting guard tokens".into());
    }
    let tokens: Vec<_> = tokens
        .tokens
        .iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect();
    if tokens.first().is_none_or(|token| token.text(text) != "(") {
        return Err("setting guard requires parentheses".into());
    }
    let mut depth = 0;
    let mut closing = None;
    for (index, token) in tokens.iter().enumerate() {
        match token.text(text) {
            "(" => depth += 1,
            ")" => {
                depth -= 1;
                if depth == 0 {
                    closing = Some((index, token.span));
                    break;
                }
            }
            _ => {}
        }
    }
    let (index, closing) = closing.ok_or("unterminated setting guard")?;
    if index + 1 != tokens.len() {
        return Err("unsupported text following setting guard".into());
    }
    super::procedure::expression(&text[tokens[0].span.end..closing.start], symbols)
}

fn conditional_chain(
    header: &str,
    children: &[Item],
    else_items: &[Item],
    symbols: &mut SymbolTable,
) -> Result<ProcedureSettingNode, String> {
    let guard = condition(header, symbols)?;
    let then_branch = extract_settings(children, symbols)?;
    let else_branch = if let Some(other) = else_items.first() {
        let header = other.header.trim();
        if header == "else" {
            if else_items.len() != 1 {
                return Err("setting chain has clauses after else".into());
            }
            extract_settings(&other.children, symbols)?
        } else {
            let header = header
                .strip_prefix("else")
                .ok_or("invalid setting else clause")?
                .trim_start();
            if !keyword(header, "if") {
                return Err("unsupported setting else clause".into());
            }
            vec![conditional_chain(
                header,
                &other.children,
                &else_items[1..],
                symbols,
            )?]
            .into()
        }
    } else {
        Arc::from([])
    };
    Ok(ProcedureSettingNode::Conditional {
        condition: guard,
        then_branch,
        else_branch,
    })
}

/// Input must be the compact setting-context projection, in source order.
/// No condition is evaluated here and no unsupported ancestor is discarded.
pub fn extract_settings(
    items: &[Item],
    symbols: &mut SymbolTable,
) -> Result<Arc<[ProcedureSettingNode]>, String> {
    let mut result = Vec::new();
    let mut index = 0;
    while index < items.len() {
        let item = &items[index];
        let header = item.header.trim();
        if keyword(header, "if") {
            let end = chain_end(items, index);
            if items[index..end].iter().any(has_setting) {
                result.push(conditional_chain(
                    header,
                    &item.children,
                    &items[index + 1..end],
                    symbols,
                )?);
            }
            index = end;
            continue;
        }
        if keyword(header, "else") {
            return Err("setting else has no preceding if".into());
        }
        if keyword(header, "set") {
            if !item.children.is_empty() {
                return Err("setting has nested children".into());
            }
            result.push(ProcedureSettingNode::Setting(
                super::procedure::parse_setting(header, symbols)?,
            ));
        } else if item.children.iter().any(has_setting) {
            result.push(ProcedureSettingNode::UnsupportedContext {
                canonical_header: super::procedure::expression(header, symbols)?,
                children: extract_settings(&item.children, symbols)?,
            });
        }
        index += 1;
    }
    Ok(result.into())
}

/// Source-only spans remain outside canonical setting-node identities.
pub(crate) fn setting_spans(items: &[Item], output: &mut Vec<Span>) {
    for item in items {
        output.push(item.header_span);
        setting_spans(&item.children, output);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn projection(source: &str) -> (Vec<Item>, Arc<[ProcedureSettingNode]>) {
        let mut ast = dm_syntax::parse(source);
        assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
        let body = std::mem::take(&mut ast.items[0].children);
        let mut symbols = SymbolTable::default();
        let full = extract_settings(&body, &mut symbols).unwrap();
        let compact = compact_setting_items(body);
        let extracted = extract_settings(&compact, &mut symbols).unwrap();
        assert_eq!(full, extracted);
        (compact, extracted)
    }
    #[test]
    fn complete_if_else_chain_retains_empty_antecedent_and_order() {
        let (compact, nodes) = projection("/proc/p()\n    if (FIRST)\n        return 1\n    else if (SECOND)\n        set waitfor = 0\n        return 2\n    else\n        set waitfor = 1\n    set background = 0\n    return 3\n");
        assert_eq!(compact.len(), 4);
        assert!(compact[0].children.is_empty());
        assert_eq!(compact[1].children.len(), 1);
        assert_eq!(nodes.len(), 2);
        let ProcedureSettingNode::Conditional {
            then_branch,
            else_branch,
            ..
        } = &nodes[0]
        else {
            panic!("missing conditional")
        };
        assert!(then_branch.is_empty());
        let ProcedureSettingNode::Conditional {
            then_branch,
            else_branch,
            ..
        } = &else_branch[0]
        else {
            panic!("missing else-if")
        };
        assert_eq!(then_branch.len(), 1);
        assert_eq!(else_branch.len(), 1);
    }
    #[test]
    fn unsupported_control_context_is_preserved_not_evaluated() {
        let (compact, nodes) = projection("/proc/p()\n    while (runtime_value)\n        if (FLAG)\n            set background = 1\n        sleep(1)\n    return 2\n");
        assert_eq!(compact.len(), 1);
        assert_eq!(compact[0].children.len(), 1);
        assert!(
            matches!(&nodes[0], ProcedureSettingNode::UnsupportedContext { children, .. }
            if matches!(&children[0], ProcedureSettingNode::Conditional { .. }))
        );
    }
    #[test]
    fn ordinary_control_flow_does_not_enter_setting_projection() {
        let (compact, nodes) = projection(
            "/proc/p()\n    if (runtime_value)\n        return 1\n    else\n        return 2\n",
        );
        assert!(compact.is_empty());
        assert!(nodes.is_empty());
    }
    #[test]
    fn executable_projection_preserves_mixed_chain_and_drops_setting_only_chain() {
        let mut ast = dm_syntax::parse("/proc/p()\n    if (1)\n        set waitfor = 0\n    else\n        return 2\n    if (0)\n        set background = 1\n    else\n        set background = 0\n    return 3\n");
        let body = strip_setting_items(std::mem::take(&mut ast.items[0].children));
        assert_eq!(body.len(), 3);
        assert_eq!(body[0].header, "if (1)");
        assert!(body[0].children.is_empty());
        assert_eq!(body[1].header, "else");
        assert_eq!(body[1].children[0].header, "return 2");
        assert_eq!(body[2].header, "return 3");
    }
}
