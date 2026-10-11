//! Finite pure-call semantics certified by the pinned native RGB receipts.
use dm_tree::constants::{Constant, PureCallError, PureCalls};

pub struct PinnedPureCalls {
    identity: u128,
}
impl PinnedPureCalls {
    pub fn new(engine: &crate::engine::EngineSnapshot) -> Result<Self, String> {
        if !engine.matches_template(include_bytes!("../../../fixtures/native_template.bin"), 1) {
            return Err("pure RGB policy requires the pinned BYOND 516.1687 template".into());
        }
        let mut bytes = b"byond5161687-rgb-v1:3or4-finite-numeric:clamp-truncate-lowerhex".to_vec();
        bytes.extend_from_slice(&engine.template_identity().to_le_bytes());
        bytes.extend_from_slice(
            &xxhash_rust::xxh3::xxh3_128(include_bytes!(
                "../../../fixtures/phase1/native_rgb_initializers/positive.native.bin"
            ))
            .to_le_bytes(),
        );
        Ok(Self {
            identity: xxhash_rust::xxh3::xxh3_128(&bytes),
        })
    }
}
impl PureCalls for PinnedPureCalls {
    fn immutable_policy_identity(&self) -> Option<u128> {
        Some(self.identity)
    }
    fn immutable_policy_bytes(&self) -> Option<&[u8]> {
        // The engine template is authenticated separately, without hash-only
        // admission. Include the complete native evidence, not its digest.
        static EVIDENCE: std::sync::OnceLock<Vec<u8>> = std::sync::OnceLock::new();
        Some(EVIDENCE.get_or_init(|| {
            let mut bytes =
                b"byond5161687-rgb-v1:3or4-finite-numeric:clamp-truncate-lowerhex\0".to_vec();
            bytes.extend_from_slice(include_bytes!(
                "../../../fixtures/phase1/native_rgb_initializers/positive.native.bin"
            ));
            bytes
        }))
    }
    fn identity(&self) -> u128 {
        self.identity
    }
    fn accepts(&self, name: &str) -> bool {
        name == "rgb"
    }
    fn evaluate(
        &self,
        name: &str,
        arguments: &[Option<Constant>],
    ) -> Result<Constant, PureCallError> {
        let reject = |reason: &str| PureCallError {
            name: name.into(),
            reason: reason.into(),
        };
        if name != "rgb" {
            return Err(reject("call is not admitted by the RGB policy"));
        }
        if !matches!(arguments.len(), 3 | 4) {
            return Err(reject(
                "only certified three/four-component rgb forms are supported",
            ));
        }
        let mut text = String::from("#");
        for argument in arguments {
            let Some(Constant::Number(number)) = argument else {
                return Err(reject("rgb components must be captured constant numbers"));
            };
            if !number.is_finite() {
                return Err(reject("nonfinite rgb components are not certified"));
            }
            use std::fmt::Write;
            write!(&mut text, "{:02x}", number.clamp(0.0, 255.0).trunc() as u8)
                .expect("writing a String cannot fail");
        }
        Ok(Constant::Text(text))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pinned_rgb_folds_native_values_and_rejects_unavailable_arguments() {
        let policy = PinnedPureCalls { identity: 1 };
        for (source, expected) in [
            ("rgb(255,201,49)", "#ffc931"),
            ("rgb(255,201,49,128)", "#ffc93180"),
            ("rgb(12.9,0.9,254.9)", "#0c00fe"),
            ("rgb(-5,300,512)", "#00ffff"),
            ("rgb(RED,201,49)", "#ffc931"),
        ] {
            let result = dm_tree::constants::evaluate_with_resources_and_calls(
                source,
                |name| (name == "RED").then_some(Constant::Number(255.0)),
                |_| None,
                |_| None,
                |_| None,
                Some(&policy),
            );
            assert_eq!(result, Ok(Some(Constant::Text(expected.into()))));
        }
        for source in [
            "rgb(runtime,201,49)",
            "rgb(rand(0,255),201,49)",
            "rgb(1,2)",
            "rgb(1,2,3,4,5)",
        ] {
            assert!(dm_tree::constants::evaluate_with_resources_and_calls(
                source,
                |_| None,
                |_| None,
                |_| None,
                |_| None,
                Some(&policy)
            )
            .is_err());
        }
        assert_eq!(
            dm_tree::constants::evaluate_with("rgb(1,2,3)", |_| None, |_| None, |_| None),
            None
        );
        let reads = std::cell::Cell::new(0);
        assert_eq!(
            dm_tree::constants::evaluate_with_resources_and_calls(
                "runtime_call(unknown)",
                |_| {
                    reads.set(reads.get() + 1);
                    None
                },
                |_| None,
                |_| None,
                |_| None,
                Some(&policy)
            ),
            Ok(None)
        );
        assert_eq!(reads.get(), 0);
        assert_eq!(
            dm_tree::constants::evaluate_with_resources_and_calls(
                "1 || rgb(runtime,1,2)",
                |_| None,
                |_| None,
                |_| None,
                |_| None,
                Some(&policy)
            ),
            Ok(Some(Constant::Number(1.0)))
        );
    }
}
