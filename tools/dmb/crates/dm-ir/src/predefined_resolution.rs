//! Target-independent predefined constant selection. Query timing belongs to
//! the host: the text candidate is observed only after a numeric miss.
use crate::SemanticValue;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PredefinedValueError {
    UnsupportedValue,
    InvalidUtf8,
}

pub fn numeric_value(value: Option<SemanticValue>) -> Result<Option<u32>, PredefinedValueError> {
    match value {
        Some(SemanticValue::NumberBits(bits)) => Ok(Some(bits)),
        Some(SemanticValue::Text(_)) | None => Ok(None),
        _ => Err(PredefinedValueError::UnsupportedValue),
    }
}

pub fn text_value(value: Option<SemanticValue>) -> Result<Option<String>, PredefinedValueError> {
    match value {
        Some(SemanticValue::Text(bytes)) => std::str::from_utf8(&bytes)
            .map(|text| Some(text.to_owned()))
            .map_err(|_| PredefinedValueError::InvalidUtf8),
        Some(SemanticValue::NumberBits(_)) | None => Ok(None),
        _ => Err(PredefinedValueError::UnsupportedValue),
    }
}

pub trait PredefinedContext {
    type Error;
    fn numeric_candidate(&self, name: &str) -> Result<Option<u32>, Self::Error>;
    fn text_candidate(&self, name: &str) -> Result<Option<String>, Self::Error>;
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum PredefinedConstant {
    NumberBits(u32),
    Text(String),
}

pub fn select_predefined<C: PredefinedContext>(
    context: &C,
    name: &str,
) -> Result<Option<PredefinedConstant>, C::Error> {
    if let Some(bits) = context.numeric_candidate(name)? {
        return Ok(Some(PredefinedConstant::NumberBits(bits)));
    }
    context
        .text_candidate(name)
        .map(|value| value.map(PredefinedConstant::Text))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{cell::RefCell, sync::Arc};
    struct Host {
        values: RefCell<Vec<Option<SemanticValue>>>,
        calls: RefCell<Vec<&'static str>>,
    }
    impl PredefinedContext for Host {
        type Error = PredefinedValueError;
        fn numeric_candidate(&self, _: &str) -> Result<Option<u32>, Self::Error> {
            self.calls.borrow_mut().push("numeric");
            numeric_value(self.values.borrow_mut().remove(0))
        }
        fn text_candidate(&self, _: &str) -> Result<Option<String>, Self::Error> {
            self.calls.borrow_mut().push("text");
            text_value(self.values.borrow_mut().remove(0))
        }
    }
    #[test]
    fn numeric_selection_stops_observation_and_text_requires_its_own_current_answer() {
        let host = Host {
            values: RefCell::new(vec![Some(SemanticValue::NumberBits(0x7fc0_1234))]),
            calls: RefCell::new(Vec::new()),
        };
        assert_eq!(
            select_predefined(&host, "value"),
            Ok(Some(PredefinedConstant::NumberBits(0x7fc0_1234)))
        );
        assert_eq!(*host.calls.borrow(), vec!["numeric"]);
        let host = Host {
            values: RefCell::new(vec![
                Some(SemanticValue::Text(Arc::from(b"first".as_slice()))),
                Some(SemanticValue::Text(Arc::from(b"second".as_slice()))),
            ]),
            calls: RefCell::new(Vec::new()),
        };
        assert_eq!(
            select_predefined(&host, "value"),
            Ok(Some(PredefinedConstant::Text("second".into())))
        );
        assert_eq!(*host.calls.borrow(), vec!["numeric", "text"]);
    }
    #[test]
    fn unsupported_values_short_circuit_and_utf8_validation_occurs_only_for_text() {
        let host = Host {
            values: RefCell::new(vec![Some(SemanticValue::Null)]),
            calls: RefCell::new(Vec::new()),
        };
        assert_eq!(
            select_predefined(&host, "value"),
            Err(PredefinedValueError::UnsupportedValue)
        );
        assert_eq!(*host.calls.borrow(), vec!["numeric"]);
        let bytes = Some(SemanticValue::Text(Arc::from([0xff_u8].as_slice())));
        assert_eq!(numeric_value(bytes.clone()), Ok(None));
        assert_eq!(text_value(bytes), Err(PredefinedValueError::InvalidUtf8));
        assert_eq!(text_value(Some(SemanticValue::NumberBits(1))), Ok(None));
    }
}
