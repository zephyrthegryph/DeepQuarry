//! Captured savefile header property; this is not an instance variable record.
use dm_ir::{InitializerTarget, SemanticValue, SymbolId, SymbolTable};

pub fn is_header_target(target: &InitializerTarget, _symbols: &SymbolTable) -> bool {
    matches!(target, InitializerTarget::Instance { declaring_owner, receiver_owner, name }
        if *declaring_owner == SymbolId::of("/savefile")
            && *receiver_owner == SymbolId::of("/savefile")
            && *name == SymbolId::of("byond_version"))
}

pub fn project(value: &SemanticValue) -> Result<u32, String> {
    let SemanticValue::NumberBits(bits) = value else {
        return Err("invalid /savefile/byond_version: expected an integer".into());
    };
    let number = f32::from_bits(*bits);
    if !number.is_finite() || number < 0.0 || number.fract() != 0.0 || number >= u32::MAX as f32 {
        return Err("invalid /savefile/byond_version: expected a nonnegative u32 integer".into());
    }
    Ok(number as u32)
}

/// Ordered authored directives replace the captured value. No directives retain
/// the incoming engine value. Compatibility framing follows the pinned writer.
pub fn apply(dmb: &mut byond_dmb::dmb::Dmb, values: &[u32]) -> Result<(), String> {
    for &value in values {
        let compatibility = std::str::from_utf8(&dmb.header.compatibility_line)
            .ok()
            .and_then(|line| line.strip_prefix("min compatibility v"))
            .and_then(|tail| tail.split_whitespace().next())
            .and_then(|version| version.parse::<u16>().ok())
            .ok_or("invalid compatibility header")?;
        dmb.world.savefile_byond_version = value;
        if value != 0 && compatibility <= 514 {
            dmb.header.compatibility_line = b"min compatibility v515 468\n".to_vec();
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_savefile_version_and_integer_constraints() {
        let native = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_compiler/savefile_version/probe.native.bin"
        ))
        .unwrap();
        assert_eq!(
            native.world.savefile_byond_version,
            project(&SemanticValue::NumberBits(512f32.to_bits())).unwrap()
        );
        for value in [-1.0, 0.5, f32::INFINITY, f32::NAN, u32::MAX as f32] {
            assert!(project(&SemanticValue::NumberBits(value.to_bits())).is_err());
        }
        assert!(project(&SemanticValue::Null).is_err());
        let mut output = native.clone();
        apply(&mut output, &[]).unwrap();
        assert_eq!(output.world.savefile_byond_version, 512);
        apply(&mut output, &[516, 0, 512]).unwrap();
        assert_eq!(output.world.savefile_byond_version, 512);
    }
}
