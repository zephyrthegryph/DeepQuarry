//! Context-free directive syntax captured during the existing parallel lexical pass.
use crate::Macro;
use std::ops::Range;
#[derive(Clone, Debug)]
pub(crate) struct DirectiveSyntax {
    word: Range<usize>,
    rest: Range<usize>,
    pub(crate) definition: Option<Result<(String, Macro), String>>,
    pub(crate) identifier: Option<Result<String, String>>,
}
impl DirectiveSyntax {
    pub(super) fn visit_storage(&self, visit: &mut impl FnMut(super::PreparedSourceStorage<'_>)) {
        use super::PreparedSourceStorage as View;
        if let Some(definition) = &self.definition {
            match definition {
                Ok((name, definition)) => {
                    visit(View::String(name));
                    visit(View::Macro(definition));
                }
                Err(error) => visit(View::String(error)),
            }
        }
        if let Some(identifier) = &self.identifier {
            match identifier {
                Ok(value) | Err(value) => visit(View::String(value)),
            }
        }
    }

    pub(crate) fn new(text: &str) -> Option<Self> {
        let directive = text.trim_start().strip_prefix('#')?.trim_start();
        let (word, rest) = crate::split_word(directive);
        let offset = text.len() - directive.len();
        let rest_offset = text.len() - rest.len();
        Some(Self {
            word: offset..offset + word.len(),
            rest: rest_offset..text.len(),
            definition: (word == "define").then(|| crate::parse_define(rest)),
            identifier: (word == "undef")
                .then(|| crate::directive_identifier(rest).map(str::to_owned)),
        })
    }
    pub(crate) fn parts<'a>(&self, text: &'a str) -> (&'a str, &'a str) {
        (&text[self.word.clone()], &text[self.rest.clone()])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn storage_exposure_shares_arrays_and_visits_owned_directive_payloads() {
        use super::super::{PreparedSource, PreparedSourceStorage};
        let source = PreparedSource::new(std::sync::Arc::from(
            "#define JOIN(a,b) a##b\n#undef JOIN\n#define BAD(a\nvar/value = 1\n",
        ));
        let clone = source.clone();
        let buffers = |source: &PreparedSource| {
            let mut values = Vec::new();
            source.visit_storage(|view| {
                if let PreparedSourceStorage::Buffer { address, bytes } = view {
                    values.push((address, bytes));
                }
            });
            values
        };
        assert_eq!(buffers(&source), buffers(&clone));
        assert_eq!(buffers(&source).len(), 3);
        assert!(buffers(&source).iter().all(|(_, bytes)| *bytes > 0));
        let mut strings = Vec::new();
        let mut macros = 0;
        source.visit_storage(|view| match view {
            PreparedSourceStorage::String(value) => strings.push(value.clone()),
            PreparedSourceStorage::Macro(value) => {
                macros += 1;
                assert_eq!(value.parameters.as_ref().unwrap(), &["a", "b"]);
                assert_eq!(value.replacement, "a##b");
            }
            PreparedSourceStorage::Buffer { .. } => (),
        });
        assert_eq!(macros, 1);
        assert_eq!(
            strings
                .iter()
                .filter(|value| value.as_str() == "JOIN")
                .count(),
            2
        );
        assert_eq!(strings.len(), 3); // definition name, undef name, deferred error
    }

    #[test]
    fn prepared_parts_and_syntax_preserve_whitespace_and_deferred_errors() {
        for text in [
            "  #define VALUE 3\r\n",
            "\t# define JOIN(a,b) a##b\n",
            "#undef VALUE\n",
            "#if VALUE\n",
            "#include \"file.dm\"\n",
            "#unknown thing\n",
            "#define BAD(a\n",
            "#undef BAD EXTRA\n",
            "#\n",
        ] {
            let parsed = DirectiveSyntax::new(text).unwrap();
            let expected =
                crate::split_word(text.trim_start().strip_prefix('#').unwrap().trim_start());
            assert_eq!(parsed.parts(text), expected);
            if expected.0 == "define" {
                assert_eq!(
                    parsed.definition.as_ref().unwrap(),
                    &crate::parse_define(expected.1)
                );
            }
            if expected.0 == "undef" {
                assert_eq!(
                    parsed.identifier.as_ref().unwrap(),
                    &crate::directive_identifier(expected.1).map(str::to_owned)
                );
            }
        }
        assert!(DirectiveSyntax::new("    text #define LOOKS_LIKE_DIRECTIVE").is_none());
        assert!(DirectiveSyntax::new("#define BAD(a\n")
            .unwrap()
            .definition
            .unwrap()
            .is_err());
    }
}
