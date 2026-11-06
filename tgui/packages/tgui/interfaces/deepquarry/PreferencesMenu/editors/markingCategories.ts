// What a player looks for in the marking picker. The catalog has no category of its own, so this decides in order:
// the explicit table (names no rule reads right), what the name says it is (a tattoo, a bandage, a species' part,
// a body shape), then where body_parts puts it. A marking spanning several regions is Full body; Other is only a
// marking with no body parts. markingSubgroup() then sorts a big category into headed groups.

export const MARKING_CATEGORIES = [
  'Full body',
  'Head',
  'Eyes & brows',
  'Snout & mouth',
  'Hair, ears & horns',
  'Torso',
  'Arms & hands',
  'Legs & feet',
  'Body shape',
  'Species',
  'Robotic',
  'Tattoos & paint',
  'Scars',
  'Bandages',
  'Other',
] as const;

export type MarkingCategory = (typeof MARKING_CATEGORIES)[number];

/// Names the rules below read wrong, by exact marking name.
const EXPLICIT: Record<string, MarkingCategory> = {
  'Blank round face (use with monster mouth)': 'Head',
  Monoeye: 'Eyes & brows',
  Bridge: 'Snout & mouth',
  'Horse Fringe': 'Hair, ears & horns',
  'Sylveon Head Ribbons': 'Hair, ears & horns',
  'Secretary Bird Feathers': 'Hair, ears & horns',
  'Round (Humanoid)': 'Body shape',
  Bindi: 'Tattoos & paint',
  Tilaka: 'Tattoos & paint',
};

/// Species keyword -> the group it heads in Species.
const SPECIES_GROUPS: Array<[RegExp, string]> = [
  [/\bvox\b/, 'Vox'],
  [/\b(teshari|tesh)\b/, 'Teshari'],
  [/\b(tajaran?|taj)\b/, 'Tajaran'],
  [/\b(unathi|una)\b/, 'Unathi'],
  [/\bskrell\b/, 'Skrell'],
  [/\bdiona\b/, 'Diona'],
  [/\bsergal\b/, 'Sergal'],
  [/\bzorren\b/, 'Zorren'],
  [/\bakula\b/, 'Akula'],
  [/\b(nevrean|nev|nev\/rap|rapala)\b/, 'Nevrean & Rapala'],
  [/\b(vulpkanin|vulp)\b/, 'Vulpkanin'],
  [/\baltevian\b/, 'Altevian'],
  [/\bxenomorph\b/, 'Xenomorph'],
  [/\btyranid\b/, 'Tyranid'],
  [/\bnightstalker\b/, 'Nightstalker'],
  [/\bsect drone\b/, 'Sect Drone'],
  [/\bshadekin\b/, 'Shadekin'],
  [/\breplikant\b/, 'Replikant'],
  [/\b(protean|alraune)\b/, 'Other species'],
];
const ROBOTIC =
  /\b(augment|aug|cyber\w*|robot\w*|prosthe\w*|implant|synth\w*|panels?|lights|ipc|fbp|protogen|yr3)\b/;
const BODY_SHAPE =
  /\b(bodytype|breasts|bust|bustier|abs|six pack|chubby|soft belly|nipples|thick(er)? (neck|throat)|boosted thighs|body ton\w+)\b/;
const PAINT = /\b(paint|hazard)\b/;

const REGIONS: Array<[string, string[]]> = [
  ['Head', ['head']],
  ['Torso', ['torso', 'groin']],
  ['Arms', ['l_arm', 'r_arm', 'l_hand', 'r_hand']],
  ['Legs', ['l_leg', 'r_leg', 'l_foot', 'r_foot']],
];
const regionsOf = (bodyParts: string[]) =>
  REGIONS.filter(([, zones]) => bodyParts.some((p) => zones.includes(p))).map(
    ([label]) => label,
  );

export const markingCategory = (
  name: string,
  bodyParts: string[],
): MarkingCategory => {
  const explicit = EXPLICIT[name];
  if (explicit) return explicit;
  const n = name.toLowerCase();
  if (/\b(bandage|gauze|sling)\b/.test(n)) return 'Bandages';
  if (/\b(scars?|stitch\w*|burn)\b/.test(n)) return 'Scars';
  if (/\b(tattoo|tat|brand)\b/.test(n) || PAINT.test(n))
    return 'Tattoos & paint';
  if (ROBOTIC.test(n)) return 'Robotic';
  if (SPECIES_GROUPS.some(([re]) => re.test(n))) return 'Species';
  if (BODY_SHAPE.test(n)) return 'Body shape';
  if (/\b(digi\w*|big ?leg\w*|leggy)\b/.test(n)) return 'Legs & feet';
  if (bodyParts.length === 0) return 'Other';
  const regions = regionsOf(bodyParts);
  if (bodyParts.length >= 6 || regions.length > 1) {
    // Groin plus legs is still the legs.
    if (
      !bodyParts.includes('torso') &&
      !regions.includes('Head') &&
      !regions.includes('Arms')
    )
      return 'Legs & feet';
    return 'Full body';
  }
  switch (regions[0]) {
    case 'Head':
      if (
        /\b(mono)?eye\w*|\b(brow\w*|lash\w*|pupil\w*|heterochromia)\b/.test(n)
      )
        return 'Eyes & brows';
      if (
        /\b(snout|snoot|muzzle|nose|nostrils?|whiskers?|beak|mouth|lip\w*|fang\w*|teeth|tusk\w*|jaw|cheek\w*)\b/.test(
          n,
        )
      )
        return 'Snout & mouth';
      if (
        /\b(hair|ears?|horns?|antenna\w*|frills?|fins?|mane|spines?|crest)\b/.test(
          n,
        )
      )
        return 'Hair, ears & horns';
      return 'Head';
    case 'Torso':
      return 'Torso';
    case 'Arms':
      return 'Arms & hands';
    default:
      return 'Legs & feet';
  }
};

/// The headed group inside a category, or '' for a category that stays one flat list.
export const markingSubgroup = (
  category: MarkingCategory,
  name: string,
  bodyParts: string[],
): string => {
  const n = name.toLowerCase();
  switch (category) {
    case 'Species':
      return SPECIES_GROUPS.find(([re]) => re.test(n))?.[1] ?? '';
    case 'Robotic': {
      if (/\baugment\b/.test(n)) return 'Augments';
      if (/\bprotogen\b/.test(n)) return 'Protogen';
      if (/\byr3\b/.test(n)) return 'YR3';
      if (/\bcyber/.test(n)) return 'Cyber';
      return 'Manufacturer panels & lights';
    }
    case 'Scars':
    case 'Bandages':
    case 'Tattoos & paint': {
      const regions = regionsOf(bodyParts);
      return regions.length === 1 ? regions[0] : 'Several';
    }
    case 'Snout & mouth':
      if (/\bbeak\b/.test(n)) return 'Beaks';
      if (/\b(teeth|fang\w*|tusk\w*)\b/.test(n)) return 'Teeth';
      if (/\bjaw\b/.test(n)) return 'Jaws';
      if (/\b(nose|nostrils?)\b/.test(n)) return 'Noses';
      if (/\bcheek\w*\b/.test(n)) return 'Cheeks';
      if (/\b(snout|snoot|muzzle)\b/.test(n)) return 'Snouts & muzzles';
      return 'Mouth & other';
    case 'Legs & feet':
      if (/\bdigi/.test(n)) return 'Digitigrade';
      if (/\b(big ?leg\w*)\b/.test(n)) return 'Big legs';
      if (/\b(hoof|hooves|talons?|paws?|toes?)\b/.test(n))
        return 'Hooves & talons';
      return 'Plantigrade';
    default:
      return '';
  }
};
