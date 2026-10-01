//! Discover resources in ordinary expressions and nested string interpolation.

use dm_syntax::quoted_end;

pub(crate) fn visit_resources<'src>(source: &'src str, visitor: &mut impl FnMut(&'src str)) {
    scan_expressions(source, false, true, visitor);
}

/// Maps contain constant literal values. Match the ordinary lexer's Resource
/// tokens without treating interpolated string text as map asset expressions.
pub(super) fn visit_literal_resources<'src>(
    source: &'src str,
    visitor: &mut impl FnMut(&'src str),
) {
    scan_expressions(source, false, false, visitor);
}

/// Skip uninteresting expression bytes without creating identifiers, numbers,
/// punctuation tokens, or a token vector for the rest of an interpolation.
/// Return the byte immediately after the matching interpolation bracket.
fn scan_expressions<'src>(
    source: &'src str,
    interpolation: bool,
    discover_interpolation: bool,
    visitor: &mut impl FnMut(&'src str),
) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut pos = 0;
    let mut depth = usize::from(interpolation);
    while pos < bytes.len() {
        match bytes[pos] {
            b'/' if bytes.get(pos + 1) == Some(&b'/') => {
                pos += 2;
                while pos < bytes.len() && !matches!(bytes[pos], b'\r' | b'\n') {
                    pos += 1;
                }
            }
            b'/' if bytes.get(pos + 1) == Some(&b'*') => {
                pos += 2;
                let mut comments = 1usize;
                while pos + 1 < bytes.len() && comments > 0 {
                    match (bytes[pos], bytes[pos + 1]) {
                        (b'/', b'*') => {
                            comments += 1;
                            pos += 2;
                        }
                        (b'*', b'/') => {
                            comments -= 1;
                            pos += 2;
                        }
                        _ => pos += 1,
                    }
                }
                if comments > 0 {
                    return None;
                }
            }
            b'@' if bytes.get(pos + 1) == Some(&b'\'') => {
                let end = source[pos + 2..].find('\'').map(|at| pos + at + 3);
                pos = end.unwrap_or(bytes.len());
            }
            b'@' if source[pos..].starts_with("@{\"") => {
                let end = quoted_end(&source[pos + 1..], true, true);
                pos = end.map_or(bytes.len(), |end| pos + 1 + end);
            }
            b'@' if bytes.get(pos + 1) == Some(&b'"') => {
                let end = quoted_end(&source[pos + 1..], false, true);
                pos = end.map_or(bytes.len(), |end| pos + 1 + end);
            }
            b'{' if bytes.get(pos + 1) == Some(&b'"') => {
                let end =
                    quoted_end(&source[pos..], true, false).map_or(bytes.len(), |end| pos + end);
                if discover_interpolation {
                    visit_string(&source[pos..end], visitor);
                }
                pos = end;
            }
            b'"' => {
                let end =
                    quoted_end(&source[pos..], false, false).map_or(bytes.len(), |end| pos + end);
                if discover_interpolation {
                    visit_string(&source[pos..end], visitor);
                }
                pos = end;
            }
            b'\'' => {
                let start = pos;
                pos += 1;
                while pos < bytes.len() {
                    if bytes[pos] == b'\\' {
                        pos = (pos + 2).min(bytes.len());
                    } else if bytes[pos] == b'\'' {
                        pos += 1;
                        break;
                    } else {
                        pos += 1;
                    }
                }
                visitor(&source[start..pos]);
            }
            b'[' if interpolation => {
                depth += 1;
                pos += 1;
            }
            b']' if interpolation => {
                depth -= 1;
                pos += 1;
                if depth == 0 {
                    return Some(pos);
                }
            }
            _ => pos += 1,
        }
    }
    None
}

fn visit_string<'src>(value: &'src str, visitor: &mut impl FnMut(&'src str)) {
    let bytes = value.as_bytes();
    let mut offset = if value.starts_with("{\"") { 2 } else { 1 };
    while offset < bytes.len() {
        match bytes[offset] {
            b'\\' => offset = (offset + 2).min(bytes.len()),
            b'[' => {
                offset += 1;
                let Some(end) = scan_expressions(&value[offset..], true, true, visitor) else {
                    return;
                };
                offset += end;
            }
            _ => offset += 1,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Retain the general lexer as an independent compatibility oracle. In
    // particular, nested interpolation must not discover quoted literal text.
    fn reference_resources(source: &str, found: &mut Vec<String>) {
        dm_syntax::visit_tokens(source, |token| match token.kind {
            dm_syntax::TokenKind::Resource => found.push(token.text(source).into()),
            dm_syntax::TokenKind::String => reference_string(token.text(source), found),
            _ => {}
        });
    }

    fn reference_string(value: &str, found: &mut Vec<String>) {
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
                for token in dm_syntax::lex_spans(tail).tokens {
                    match token.kind {
                        dm_syntax::TokenKind::Resource => found.push(token.text(tail).into()),
                        dm_syntax::TokenKind::String => reference_string(token.text(tail), found),
                        dm_syntax::TokenKind::Punctuation => match token.text(tail) {
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

    fn assert_matches_reference(source: &str, label: &str) -> usize {
        let mut reference = Vec::new();
        reference_resources(source, &mut reference);
        let mut optimized = Vec::new();
        visit_resources(source, &mut |path| optimized.push(path.to_owned()));
        assert_eq!(optimized, reference, "resource inventory differs: {label}");
        let mut literal_reference = Vec::new();
        dm_syntax::visit_tokens(source, |token| {
            if token.kind == dm_syntax::TokenKind::Resource {
                literal_reference.push(token.text(source).to_owned());
            }
        });
        let mut literal_optimized = Vec::new();
        visit_literal_resources(source, &mut |path| literal_optimized.push(path.to_owned()));
        assert_eq!(
            literal_optimized, literal_reference,
            "literal resource inventory differs: {label}"
        );
        optimized.len()
    }

    #[test]
    fn selective_scan_matches_lexer_on_raw_nested_comments_and_unicode() {
        let cases = [
            r##"@'raw [f('ignored.png')]' @"[f('ignored.png')]" @{"[f('ignored.png')]"} 'real.png'"##,
            r##"{"α [list[2][f('one.dmi')]] ["β [f('two.dmi')] \" 'literal.dmi'"]"}"##,
            "/* outer 'no' /* nested 'no' */ 'no' */ 'yes' // 'no'\n'last'",
            r##""[f('first') /* ] 'no' */ + f('second')]" 'after'"##,
            "'unicode-α.dmi' '\\α escaped.dmi' \"α \\β [f('inside')]\"",
            "'unterminated",
            "\"[f('resource')",
            "/* unterminated 'not-resource'",
            r##""[list["[f('nested')]" ][2]] ['next']""##,
        ];
        for source in cases {
            assert_matches_reference(source, source);
        }
    }

    #[test]
    fn selective_scan_matches_fixture_and_optional_project_inventory() {
        let mut paths =
            vec![std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures")];
        if let Some(path) = std::env::var_os("DM_RESOURCE_SCAN_CORPUS") {
            paths.push(path.into());
        }
        let mut files = 0;
        let mut resources = 0;
        while let Some(path) = paths.pop() {
            if path.is_dir() {
                for entry in std::fs::read_dir(&path).unwrap() {
                    let path = entry.unwrap().path();
                    if path.is_dir()
                        || path
                            .extension()
                            .is_some_and(|ext| ext == "dm" || ext == "dme" || ext == "dmm")
                    {
                        paths.push(path);
                    }
                }
            } else {
                let source = dm_preprocess::read_source_file(&path).unwrap();
                resources += assert_matches_reference(&source, &path.display().to_string());
                files += 1;
            }
        }
        assert!(files > 100, "fixture corpus was not scanned");
        eprintln!("selective resource scanner matched {resources} resources in {files} files");
    }

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
    fn resource_visitors_can_retain_borrowed_literals_from_multiple_sources() {
        let first = String::from("'repeat.png' \"[f('inner.dmi')]\" 'repeat.png'");
        let second = String::from("'repeat.png' 'map.dmi'");
        let mut literals = std::collections::HashSet::new();
        visit_resources(&first, &mut |literal| {
            literals.insert(literal);
        });
        visit_literal_resources(&second, &mut |literal| {
            literals.insert(literal);
        });
        assert_eq!(literals.len(), 3);
        assert!(literals.contains("'repeat.png'"));
        assert!(literals.contains("'inner.dmi'"));
        assert!(literals.contains("'map.dmi'"));
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
