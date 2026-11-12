import type { PAICardData } from '../generated/PAICard';

export type Data = PAICardData;

export type ActivePAIData = NonNullable<Data['active_pai_data']>;

export type InvitePAIData = NonNullable<Data['available_pais']>[number];

// The invite list rows have no description or comments; the previewed one has them.
export type DetailedInvitePAIData = InvitePAIData &
  Partial<
    Pick<NonNullable<Data['selected_pai_data']>, 'description' | 'comments'>
  >;

export type RadioData = ActivePAIData['radio_data'];
