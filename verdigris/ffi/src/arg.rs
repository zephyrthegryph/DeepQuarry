//! Checked decoding of the numbers DM passes to a bind. One place for it: a bare `get_number()? as u32` saturates
//! (a DM bug passing -1 or NaN becomes handle 0, a fraction is truncated) where these return an error naming the
//! argument. Integers are exact in an `f32` only below 2^24, so every whole number above that is refused too.
//!
//! The `*_of` forms take the already-read `f32`, so the rules are testable without BYOND.

use byondapi::prelude::*;
use eyre::{Result, bail};

/// Largest integer every `f32` represents exactly, plus one.
pub const EXACT_LIMIT: f32 = 16_777_216.0;

/// A number. NaN is refused; infinities pass (DM's `INFINITY` is a legitimate "unbounded").
pub fn num(v: &ByondValue) -> Result<f32> {
    num_of(v.get_number()?)
}

/// See [`num`].
pub fn num_of(n: f32) -> Result<f32> {
    if n.is_nan() {
        bail!("bad number NaN");
    }
    Ok(n)
}

/// A finite number (no NaN, no infinity).
pub fn finite(v: &ByondValue, what: &str) -> Result<f32> {
    finite_of(v.get_number()?, what)
}

/// See [`finite`].
pub fn finite_of(n: f32, what: &str) -> Result<f32> {
    if !n.is_finite() {
        bail!("bad {what} {n}: not finite");
    }
    Ok(n)
}

/// A whole number in `0..2^24`.
pub fn whole(v: &ByondValue, what: &str) -> Result<u32> {
    whole_of(v.get_number()?, what)
}

/// See [`whole`].
#[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
pub fn whole_of(n: f32, what: &str) -> Result<u32> {
    if !(n >= 0.0 && n.fract() == 0.0 && n < EXACT_LIMIT) {
        bail!("bad {what} {n}: expected a whole number in 0..{EXACT_LIMIT}");
    }
    Ok(n as u32)
}

/// A whole number in `0..2^24`, as an index.
pub fn index(v: &ByondValue, what: &str) -> Result<usize> {
    Ok(whole(v, what)? as usize)
}

/// A signed whole number in `-2^24..2^24`.
pub fn signed(v: &ByondValue, what: &str) -> Result<i32> {
    signed_of(v.get_number()?, what)
}

/// See [`signed`].
#[allow(clippy::cast_possible_truncation)]
pub fn signed_of(n: f32, what: &str) -> Result<i32> {
    if !(n.is_finite() && n.fract() == 0.0 && n.abs() < EXACT_LIMIT) {
        bail!("bad {what} {n}: expected a whole number in -{EXACT_LIMIT}..{EXACT_LIMIT}");
    }
    Ok(n as i32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whole_refuses_what_a_cast_would_saturate() {
        assert_eq!(whole_of(7.0, "x").unwrap(), 7);
        assert_eq!(whole_of(0.0, "x").unwrap(), 0);
        for bad in [-1.0, 0.5, f32::NAN, f32::INFINITY, EXACT_LIMIT, -0.5] {
            let e = whole_of(bad, "mask").unwrap_err().to_string();
            assert!(e.contains("mask"), "{e}");
        }
    }

    #[test]
    fn signed_takes_negatives_and_refuses_the_rest() {
        assert_eq!(signed_of(-3.0, "mode").unwrap(), -3);
        for bad in [1.5, f32::NAN, f32::NEG_INFINITY, EXACT_LIMIT] {
            assert!(signed_of(bad, "mode").is_err());
        }
    }

    #[test]
    fn numbers_refuse_nan_and_finite_refuses_infinity() {
        assert!(num_of(f32::NAN).is_err());
        assert_eq!(num_of(f32::INFINITY).unwrap(), f32::INFINITY);
        assert!(finite_of(f32::INFINITY, "x").is_err());
        assert_eq!(finite_of(-2.5, "x").unwrap(), -2.5);
    }
}
