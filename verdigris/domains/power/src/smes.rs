//! SMES units (and anything else that stores grid power behind a terminal):
//! a supply on the output node's region and a demand on each input
//! terminal's region. Charge is linear between power steps; Rust reports
//! the display state (`chargedisplay`, inputting, outputting) and the
//! charge, and DM never polls.

/// `SMESRATE`: watts per tick to SMES charge units.
pub const SMESRATE: f64 = 0.033_33;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SmesConfig {
    pub capacity: f64,
    pub input_level: f64,
    pub output_level: f64,
    /// `input_attempt` and not cut, pulsed, grid-checked or broken.
    pub input_enabled: bool,
    /// `output_attempt` and not cut, pulsed, grid-checked or broken.
    pub output_enabled: bool,
}

impl Default for SmesConfig {
    fn default() -> Self {
        Self {
            capacity: 5e6,
            input_level: 50_000.0,
            output_level: 50_000.0,
            input_enabled: false,
            output_enabled: true,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SmesState {
    pub charge: f64,
    /// 0 idle, 1 partial, 2 full rate.
    pub inputting: u8,
    /// 0 off, 1 wanted but no network or charge, 2 outputting.
    pub outputting: u8,
    /// Output actually consumed last step (W).
    pub output_used: f64,
    /// Input actually received last step (W).
    pub input_available: f64,
    /// Output offered to the region this step (W).
    pub offer: f64,
    /// Input requested from each terminal this step (W).
    pub target_load: f64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Smes {
    pub config: SmesConfig,
    pub state: SmesState,
    /// Input terminal node keys.
    pub terminals: Vec<u32>,
}

impl Smes {
    /// `chargedisplay()`: the five-step charge gauge.
    #[must_use]
    pub fn display(&self) -> u8 {
        let cap = if self.config.capacity > 0.0 {
            self.config.capacity
        } else {
            5e6
        };
        (5.5 * self.state.charge / cap).round() as u8
    }

    /// The output offered next step, given whether the SMES node is on a
    /// region. Sets `outputting`.
    pub fn plan_output(&mut self, connected: bool) {
        let s = &mut self.state;
        if self.config.output_enabled && connected && s.charge > 0.0 {
            s.offer = (s.charge / SMESRATE).min(self.config.output_level).max(0.0);
            s.outputting = 2;
        } else {
            s.offer = 0.0;
            s.outputting = u8::from(!connected || s.charge <= 0.0);
        }
    }

    /// The input requested per terminal next step, given whether any
    /// terminal is on a region.
    pub fn plan_input(&mut self, connected: bool) {
        let s = &mut self.state;
        s.target_load = if self.config.input_enabled && connected {
            ((self.config.capacity - s.charge) / SMESRATE).clamp(0.0, self.config.input_level)
        } else {
            0.0
        };
    }
}
