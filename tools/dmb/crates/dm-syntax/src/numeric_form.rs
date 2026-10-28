//! Lexical number shape, distinct from the runtime floating-point value.
//!
//! Int-vs-Float rules follow SpacemanDMM dreammaker lexer.rs at
//! 0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0). Invalid spellings fail;
//! the reference lexer's error-recovery Int(0) is not an authoritative fact.

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum NumericForm {
    Integer(i32),
    Float,
}

/// Classify one compiler-issued numeric literal token, without evaluating an
/// expression or rounding a floating-point value into an integer.
pub fn numeric_form(raw: &str) -> Result<NumericForm, String> {
    let text: String = raw.chars().filter(|c| *c != '_').collect();
    let invalid = || format!("unsupported or invalid numeric literal {raw:?}");
    if text.is_empty() || !matches!(text.as_bytes()[0], b'0'..=b'9' | b'.') {
        return Err(invalid());
    }
    if let Some(digits) = text.strip_prefix("0x") {
        if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_hexdigit()) {
            return Err(invalid());
        }
        return i32::from_str_radix(&format!("0{digits}"), 16)
            .map(NumericForm::Integer)
            .map_err(|_| invalid());
    }
    if text.contains('#') {
        let (prefix, suffix) = text.split_once('#').ok_or_else(invalid)?;
        return if matches!(suffix, "INF" | "IND")
            && !prefix.is_empty()
            && numeric_form(prefix.trim_end_matches('.')).is_ok()
        {
            Ok(NumericForm::Float)
        } else {
            Err(invalid())
        };
    }
    if text.bytes().any(|c| matches!(c, b'.' | b'e' | b'E')) {
        // Parsing validates spelling only; no policy receives the rounded value.
        return text
            .parse::<f32>()
            .map(|_| NumericForm::Float)
            .map_err(|_| invalid());
    }
    if !text.bytes().all(|c| c.is_ascii_digit()) {
        return Err(invalid());
    }
    let radix = if text.starts_with('0') { 8 } else { 10 };
    match i32::from_str_radix(&text, radix) {
        Ok(value) => Ok(NumericForm::Integer(value)),
        Err(_) if radix == 10 => text
            .parse::<f32>()
            .map(|_| NumericForm::Float)
            .map_err(|_| invalid()),
        Err(_) => Err(invalid()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn integer_shape_is_lexical_not_rounded() {
        for (raw, expected) in [
            ("0", 0),
            ("1", 1),
            ("01", 1),
            ("0144", 100),
            ("0x64", 100),
            ("1_00", 100),
            ("2147483647", i32::MAX),
        ] {
            assert_eq!(
                numeric_form(raw),
                Ok(NumericForm::Integer(expected)),
                "{raw}"
            );
        }
        for raw in [
            "1.0",
            "1e0",
            ".1",
            "2147483648",
            "1.#INF",
            "1.#IND",
            "2.#INF",
        ] {
            assert_eq!(numeric_form(raw), Ok(NumericForm::Float), "{raw}");
        }
    }

    #[test]
    fn malformed_or_expression_spellings_are_not_recovery_facts() {
        for raw in [
            "",
            "-1",
            "+1",
            "08",
            "0x",
            "0x80000000",
            "1+1",
            "1e",
            "nan",
            "0X1",
        ] {
            assert!(numeric_form(raw).is_err(), "{raw}");
        }
    }
}
