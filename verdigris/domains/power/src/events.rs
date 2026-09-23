//! Power's events (`rust_architecture.md` §4.8, §6). A plain enum for now
//! -- the `#[vg::events]` macro's generated DM decoder/dispatch (Core B)
//! wires these up once the FFI glue is regenerated against the new
//! components; declaring the enum here doesn't wait for that.

/// A region's power events.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PowerEvent {
    /// A region lost supply or was overdrawn.
    Brownout,
    /// A previously browned-out region recovered.
    Restored,
    /// An APC's channel settings changed (the shedding ladder, or a manual
    /// override).
    ApcChannelChanged,
}
