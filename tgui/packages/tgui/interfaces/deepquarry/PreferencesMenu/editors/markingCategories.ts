// What a player looks for in the marking picker. The catalog has no category of its own: the name decides what it
// is (a tattoo, a bandage, a species' part), then the body parts decide where it goes. Anything left is Other.

export const MARKING_CATEGORIES = [
  'Full body',
  'Head',
  'Eyes & brows',
  'Snout & mouth',
  'Hair & ears',
  'Torso',
  'Arms & hands',
  'Legs & feet',
  'Species',
  'Robotic',
  'Tattoos',
  'Scars',
  'Bandages',
  'Other',
] as const;

export type MarkingCategory = (typeof MARKING_CATEGORIES)[number];

const SPECIES =
  /\b(vox|replikant|skrell|unathi|tajaran?|taj|teshari|tesh|diona|sergal|zorren|akula|nevrean|vulpkanin|protean|alraune|altevian|xenomorph|dino)\b/;
const ROBOTIC =
  /\b(augment|aug|cyber\w*|robot\w*|prosthe\w*|implant|synth\w*|panels?|lights|ipc|fbp|protogen)\b/;

export const markingCategory = (
  name: string,
  bodyParts: string[],
): MarkingCategory => {
  const n = name.toLowerCase();
  if (/\b(bandage|gauze|sling)\b/.test(n)) return 'Bandages';
  if (/\b(scar|stitch\w*|burn)\b/.test(n)) return 'Scars';
  if (/\b(tattoo|tat|brand)\b/.test(n)) return 'Tattoos';
  if (ROBOTIC.test(n)) return 'Robotic';
  if (SPECIES.test(n)) return 'Species';
  if (/\b(digi\w*|big ?leg\w*|leggy)\b/.test(n)) return 'Legs & feet';
  const parts = new Set(bodyParts);
  const within = (...allowed: string[]) =>
    [...parts].every((p) => allowed.includes(p));
  if (parts.size >= 6) return 'Full body';
  if (parts.size === 0) return 'Other';
  if (within('head')) {
    if (/\b(eye\w*|brow\w*|lash\w*|pupil\w*|heterochromia)\b/.test(n))
      return 'Eyes & brows';
    if (
      /\b(snout|muzzle|nose|beak|mouth|lip\w*|fang\w*|teeth|tusk\w*|jaw|cheek\w*)\b/.test(
        n,
      )
    )
      return 'Snout & mouth';
    if (/\b(hair|ear\w*|horn\w*|antenna\w*|frill\w*|fin\w*|mane)\b/.test(n))
      return 'Hair & ears';
    return 'Head';
  }
  if (within('torso', 'groin')) return 'Torso';
  if (within('l_arm', 'r_arm', 'l_hand', 'r_hand')) return 'Arms & hands';
  if (within('l_leg', 'r_leg', 'l_foot', 'r_foot', 'groin'))
    return 'Legs & feet';
  return 'Other';
};
