import { flow } from 'tgui-core/fp';

import type { Crewmember } from './types';

export function getStatText(cm: Crewmember) {
  if (cm.dead) {
    return 'Deceased';
  }
  if (cm.stat === 1) {
    // Unconscious
    return 'Unconscious';
  }
  return 'Living';
}

export function getStatColor(cm: Crewmember) {
  if (cm.dead) {
    return 'red';
  }
  if (cm.stat === 1) {
    // Unconscious
    return 'orange';
  }
  return 'green';
}

// How badly off a crewmember is, for sorting: lost vitality, with the dead
// and the critical at the top.
export function getSeverity(cm: Crewmember) {
  if (cm.dead) {
    return 300;
  }
  if (cm.condition === 'critical') {
    return 200;
  }
  return 100 - (cm.vitality ?? 100);
}

const CONDITION_INFO: Record<string, { label: string; color: string }> = {
  dead: { label: 'Flatline', color: 'red' },
  critical: { label: 'Critical', color: 'red' },
  severe: { label: 'Serious', color: 'orange' },
  moderate: { label: 'Injured', color: 'yellow' },
  minor: { label: 'Fair', color: 'olive' },
  uninjured: { label: 'Stable', color: 'green' },
};

export function getConditionInfo(cm: Crewmember) {
  return CONDITION_INFO[cm.condition ?? ''] ?? null;
}

function crewStatus(
  cm: Crewmember,
  deceasedStatus: boolean,
  livingStatus: boolean,
  unconsciousStatus: boolean,
) {
  if (deceasedStatus && cm.dead) {
    return true;
  }
  if (livingStatus && !cm.dead && (!cm.stat || cm.stat < 1)) {
    return true;
  }
  if (unconsciousStatus && cm.stat === 1) {
    return true;
  }
  return false;
}

export function getShownCrew(
  crew: Crewmember[],
  locationSearch: object,
  deceasedStatus: boolean,
  livingStatus: boolean,
  unconsciousStatus: boolean,
  nameSearch: string,
  testSearch: (obj: Crewmember) => boolean,
) {
  return flow([
    (crew: Crewmember[]) => {
      if (!locationSearch) {
        return crew;
      } else {
        return crew.filter((cm) => locationSearch[cm.realZ.toString()]);
      }
    },
    (crew: Crewmember[]) => {
      return crew.filter((cm) =>
        crewStatus(cm, deceasedStatus, livingStatus, unconsciousStatus),
      );
    },
    (crew: Crewmember[]) => {
      if (!nameSearch) {
        return crew;
      } else {
        return crew.filter(testSearch);
      }
    },
  ])(crew);
}

export function getSortedCrew(
  shownCrew: Crewmember[],
  sortType: string,
  nameSortOrder: boolean,
  damageSortOrder: boolean,
  locationSortOrder: boolean,
) {
  return flow([
    (shownCrew: Crewmember[]) => {
      if (sortType === 'name') {
        const sorted = shownCrew.sort(
          (a, b) =>
            a.name.localeCompare(b.name) ||
            a.realZ - b.realZ ||
            a.x - b.x ||
            a.y - b.y,
        );
        if (nameSortOrder) {
          return sorted.reverse();
        }
        return sorted;
      } else {
        return shownCrew;
      }
    },
    (shownCrew: Crewmember[]) => {
      if (sortType === 'damage') {
        const sorted = shownCrew.sort(
          (a, b) =>
            getSeverity(a) - getSeverity(b) || a.name.localeCompare(b.name),
        );
        if (damageSortOrder) {
          return sorted.reverse();
        }
        return sorted;
      } else {
        return shownCrew;
      }
    },
    (shownCrew: Crewmember[]) => {
      if (sortType === 'location') {
        const sorted = shownCrew.sort(
          (a, b) =>
            a.realZ - b.realZ ||
            a.x - b.x ||
            a.y - b.y ||
            a.name.localeCompare(b.name),
        );
        if (locationSortOrder) {
          return sorted.reverse();
        }
        return sorted;
      } else {
        return shownCrew;
      }
    },
  ])(shownCrew);
}
