//! Discover resources in ordinary expressions and nested string interpolation.

use dm_syntax::{lex_spans, visit_tokens, TokenKind};

pub(super) fn visit_resources(source: &str, visitor: &mut impl FnMut(&str)) {
    visit_tokens(source, |token| match token.kind {
        TokenKind::Resource => visitor(token.text(source)),
        TokenKind::String => visit_string(token.text(source), visitor),
        _ => {}
    });
}

fn visit_string(value: &str, visitor: &mut impl FnMut(&str)) {
    if value.starts_with('@') {
        return;
    }
    let mut offset = if value.starts_with("{\"") { 2 } else { 1 };
    while offset < value.len() {
        let c = value[offset..].chars().next().unwrap();
        offset += c.len_utf8();
        if c == '\\' {
            if let Some(next) = value[offset..].chars().next() {
                offset += next.len_utf8();
            }
        } else if c == '[' {
            let tail = &value[offset..];
            let mut depth = 1;
            let mut end = None;
            for token in lex_spans(tail).tokens {
                match token.kind {
                    TokenKind::Resource => visitor(token.text(tail)),
                    TokenKind::String => visit_string(token.text(tail), visitor),
                    TokenKind::Punctuation => match token.text(tail) {
                        "[" => depth += 1,
                        "]" => {
                            depth -= 1;
                            if depth == 0 {
                                end = Some(token.span.end);
                                break;
                            }
                        }
                        _ => {}
                    },
                    _ => {}
                }
            }
            let Some(end) = end else {
                return;
            };
            offset += end;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn discovers_nested_interpolations_and_ignores_literal_text() {
        let source = r#"
            var/a = 'direct.png'
            var/b = "prefix [icon('nested.dmi')] [list[1]]"
            var/c = "["inner [fexists('deep.txt')]" ]"
            var/d = @"[icon('raw.dmi')]"
            var/e = "\[icon('escaped.dmi')]"
            // 'comment.dmi'
            var/f = "literal 'text.dmi'"
        "#;
        let mut found = Vec::new();
        visit_resources(source, &mut |path| found.push(path.to_owned()));
        assert_eq!(found, ["'direct.png'", "'nested.dmi'", "'deep.txt'"]);
    }

    #[test]
    fn project_links_assets_used_only_inside_string_interpolation() {
        let root = std::env::temp_dir().join(format!(
            "dm-interpolated-resource-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("test.dme"), "#include \"test.dm\"\n").unwrap();
        std::fs::write(root.join("inside.txt"), "asset").unwrap();
        std::fs::write(
            root.join("test.dm"),
            "/world/New()\n    world.log << \"[fexists('inside.txt')]\"\n    shutdown()\n",
        )
        .unwrap();
        let built = super::super::compile_project_with_resources(
            &root.join("test.dme"),
            include_bytes!("../../../fixtures/native_template.bin"),
            "test",
        )
        .unwrap();
        let entries = byond_dmb::rsc::read_all(&mut built.rsc_bytes.as_slice()).unwrap();
        assert_eq!(entries.len(), 1);
        std::fs::remove_dir_all(root).unwrap();
    }
}
