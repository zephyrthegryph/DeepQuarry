//! Pinned appearance-header direction encoding, separate from authored defaults.
use super::ProjectionError;

pub(super) fn header_direction(number: Option<f32>) -> Result<u8, ProjectionError> {
    let number = number
        .filter(|value| value.is_finite() && *value >= 0.0 && *value <= 255.0)
        .ok_or_else(|| {
            ProjectionError::Unsupported("invalid intrinsic dir numeric value".into())
        })?;
    Ok(match number as u8 {
        direction @ (1 | 2 | 4 | 5 | 6 | 8 | 9 | 10) => direction,
        _ => 2,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use byond_dmb::dmb::Dmb;

    #[test]
    fn appearance_directions_match_captured_byond_matrix() {
        let expected = Dmb::from_bytes(include_bytes!(
            "../../../../fixtures/native_compiler/header_direction/probe.native.bin"
        ))
        .unwrap();
        for input in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 16, 255] {
            let path = format!("/obj/probe/d{input}");
            let class = expected
                .classes
                .iter()
                .find(|class| expected.string(class.path_string_id()) == Some(path.as_bytes()))
                .unwrap();
            assert_eq!(
                header_direction(Some(input as f32)).unwrap(),
                class.direction,
                "{path}"
            );
        }
        let fraction = Dmb::from_bytes(include_bytes!(
            "../../../../fixtures/native_compiler/header_direction/fraction.native.bin"
        ))
        .unwrap();
        let class = fraction
            .classes
            .iter()
            .find(|class| fraction.string(class.path_string_id()) == Some(b"/obj/probe"))
            .unwrap();
        assert_eq!(header_direction(Some(4.5)).unwrap(), class.direction);
        for value in [None, Some(-1.0), Some(256.0), Some(f32::NAN)] {
            assert!(header_direction(value).is_err());
        }
    }
}
