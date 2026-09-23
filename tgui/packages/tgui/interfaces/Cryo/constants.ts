export const damageTypes: { label: string; type: string }[] = [
  {
    label: 'Resp.',
    type: 'asphyxiaLoad',
  },
  {
    label: 'Toxin',
    type: 'toxicLoad',
  },
  {
    label: 'Brute',
    type: 'physicalLoad',
  },
  {
    label: 'Burn',
    type: 'thermalLoad',
  },
];

export const statNames: string[][] = [
  ['good', 'Conscious'],
  ['average', 'Unconscious'],
  ['bad', 'DEAD'],
];
