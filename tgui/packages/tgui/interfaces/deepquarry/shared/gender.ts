// DQAdd — Shared gender util. Lifted out of bay_prefs/general/functions.ts so the bay_prefs
// tree can be deleted while PAICard (and any future consumers) keep working.

export enum Gender {
  Male = 'Male',
  Female = 'Female',
  Neuter = 'Neuter',
  Plural = 'Plural',
  Herm = 'Herm',
}

export function gender2icon(gender: Gender | string): string {
  switch (gender) {
    case Gender.Female:
      return 'venus';
    case Gender.Male:
      return 'mars';
    case Gender.Plural:
      return 'transgender';
    case Gender.Neuter:
      return 'neuter';
    case Gender.Herm:
      return 'mars-and-venus';
    default:
      return 'question';
  }
}
