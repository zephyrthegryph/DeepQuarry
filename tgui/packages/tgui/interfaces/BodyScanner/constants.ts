import type { occupant } from './types';

export const stats: string[][] = [
  ['good', 'Alive'],
  ['average', 'Unconscious'],
  ['bad', 'DEAD'],
];

export const abnormalities: (string | ((occupant: occupant) => string))[][] = [
  [
    'hasBorer',
    'bad',
    (occupant) =>
      'Large growth detected in frontal lobe,' +
      ' possibly cancerous. Surgical removal is recommended.',
  ],
  ['hasVirus', 'bad', (occupant) => 'Viral pathogen detected in blood stream.'],
  ['blind', 'average', (occupant) => 'Cataracts detected.'],
  [
    'colourblind',
    'average',
    (occupant) => 'Photoreceptor abnormalities detected.',
  ],
  ['nearsighted', 'average', (occupant) => 'Retinal misalignment detected.'],
  ['brokenspine', 'average', (occupant) => 'Lumbar spine impairement.'],
  [
    'humanPrey',
    'average',
    (occupant) => {
      return `Foreign Humanoid(s) detected: ${occupant.humanPrey}`;
    },
  ],
  [
    'livingPrey',
    'average',
    (occupant) => {
      return `Foreign Creature(s) detected: ${occupant.livingPrey}`;
    },
  ],
  [
    'objectPrey',
    'average',
    (occupant) => {
      return `Foreign Object(s) detected: ${occupant.objectPrey}`;
    },
  ],
  [
    'husked',
    'bad',
    (occupant) => 'Anatomical structure lost, resuscitation not possible!',
  ],
  [
    'hasWithdrawl',
    'bad',
    (occupant) => 'Experiencing withdrawal! Inaprovaline can reduce symptoms.',
  ],
  [
    'hasAllergens',
    'average',
    (occupant) => 'Allergic sensitivity to specific compounds detected.',
  ],
];

// Qualitative bands — used for the whole-body damage panel, the per-organ
// status pill, and the scanner-findings severity tag. The DM side
// (modular_dq/code/modules/medical/bodyscanner/qualitative.dm) picks one
// of these tokens; this table maps each to a display label and tgui-core
// colour name.
//
// Order matters: the damage panel renders bands in this order so similar
// severities cluster together when a patient has many findings.
export type DamageBand =
  | 'uninjured'
  | 'minor'
  | 'moderate'
  | 'severe'
  | 'critical';

export const BAND_INFO: Record<DamageBand, { label: string; color: string }> = {
  uninjured: { label: 'Normal', color: 'good' },
  minor: { label: 'Mild', color: 'good' },
  moderate: { label: 'Moderate', color: 'average' },
  severe: { label: 'Severe', color: 'bad' },
  critical: { label: 'Critical', color: 'bad' },
};

// Severity rank — higher = worse. Used by the occupant card to pick the
// worse of (overall health, worst scanner finding) when escalating the
// Condition row. Mirrors the DM-side _dq_band_rank helper.
export const BAND_RANK: Record<DamageBand, number> = {
  uninjured: 0,
  minor: 1,
  moderate: 2,
  severe: 3,
  critical: 4,
};
