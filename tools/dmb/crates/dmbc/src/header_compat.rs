//! Writes the `min compatibility` header line from the requirements the composed world actually has.
//! The table of features and the version-tied build rule live in `dm_ir::header_compat`.
use byond_dmb::dmb::Dmb;
use dm_ir::header_compat::HeaderCompat;

/// Merge `found` into the line already in the header (the engine baseline plus any world setting the
/// driver applied earlier). A line never goes down, and one that cannot be parsed is left alone.
pub(crate) fn apply(dmb: &mut Dmb, found: HeaderCompat) {
    let Some(mut current) = HeaderCompat::parse(&dmb.header.compatibility_line) else {
        return;
    };
    current.union(found);
    dmb.header.compatibility_line = current.line();
}

/// Raise the line to at least one feature (a world setting or savefile version the driver applies directly).
pub(crate) fn raise(dmb: &mut Dmb, version: u16, build: u16) {
    let mut feature = HeaderCompat::default();
    feature.note(version, build);
    apply(dmb, feature);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn template() -> Dmb {
        Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap()
    }

    #[test]
    fn raise_never_lowers_and_ties_builds() {
        let mut dmb = template();
        assert_eq!(dmb.header.compatibility_line, b"min compatibility v514 468\n");
        raise(&mut dmb, 514, 507);
        assert_eq!(dmb.header.compatibility_line, b"min compatibility v514 507\n");
        raise(&mut dmb, 515, 468);
        assert_eq!(dmb.header.compatibility_line, b"min compatibility v515 507\n");
        raise(&mut dmb, 516, 516);
        raise(&mut dmb, 514, 468);
        assert_eq!(dmb.header.compatibility_line, b"min compatibility v516 516\n");
    }

    #[test]
    fn unparseable_line_is_preserved() {
        let mut dmb = template();
        dmb.header.compatibility_line = b"min compatibility vX\n".to_vec();
        raise(&mut dmb, 516, 468);
        assert_eq!(dmb.header.compatibility_line, b"min compatibility vX\n");
    }
}

#[cfg(test)]
#[path = "header_compat_fixture_tests.rs"]
mod fixture_tests;
