import { useBackend } from 'tgui/backend';
import { Box, Button, Stack } from 'tgui-core/components';
import type { EditorProps } from './index';

type Faction = {
  id: string;
  name: string;
  short_name: string;
  acronym: string;
  description: string;
  color: string;
  grid_x: number;
  grid_y: number;
};

type Data = {
  affiliations: Record<string, string>;
  reputation_total: number;
  reputation_cap: number;
};

type Static = { factions: Faction[]; choices: string[] };

const AFFILIATION_COLORS: Record<string, string> = {
  Hostile: '#d94b4b',
  Opposed: '#d8894b',
  Neutral: '#9aa0aa',
  Friendly: '#58a7d8',
  Member: '#62c48d',
};

export const FactionAffiliationsEditor = ({ data, staticData }: EditorProps) => {
  const { act } = useBackend();
  const affiliations = ((data as Data).affiliations ?? {}) as Record<
    string,
    string
  >;
  const { factions = [], choices = [] } = (staticData ?? {}) as Static;

  const setAffiliation = (faction: string, affiliation: string) =>
    act('dq_editor_action', {
      editor: 'faction_affiliations',
      action: 'set_affiliation',
      params: { faction, affiliation },
    });

  if (!factions.length) {
    return (
      <Box p={2} color="label">
        Loading faction registry...
      </Box>
    );
  }

  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
        gridTemplateRows: 'repeat(3, minmax(0, 1fr))',
        gap: '8px',
        width: '100%',
        height: '100%',
        minWidth: 0,
        minHeight: 0,
        padding: '8px',
        overflow: 'hidden',
        boxSizing: 'border-box',
      }}
    >
      {factions.map((faction) => {
        const affiliation = affiliations[faction.id] ?? 'Neutral';
        return (
          <Box
            key={faction.id}
            p={1}
            style={{
              gridColumn: faction.grid_x + 1,
              gridRow: faction.grid_y + 1,
              minWidth: 0,
              minHeight: 0,
              overflow: 'hidden',
              boxSizing: 'border-box',
              border: `1px solid ${faction.color}88`,
              borderTop: `4px solid ${faction.color}`,
              borderRadius: '5px',
              background: `linear-gradient(145deg, ${faction.color}22, rgba(24,30,39,.98) 48%)`,
            }}
          >
            <Stack fill vertical>
              <Stack.Item grow basis={0} style={{ minHeight: 0 }}>
                <Stack fill align="center">
                  <Stack.Item>
                    <Box
                      style={{
                        width: '58px',
                        height: '58px',
                        borderRadius: '9px',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        background: `${faction.color}cc`,
                        border: '1px solid rgba(255,255,255,.25)',
                        color: '#fff',
                        fontWeight: 800,
                        fontSize: faction.acronym.length > 4 ? '10px' : '15px',
                        boxShadow: `0 0 12px ${faction.color}33`,
                      }}
                    >
                      {faction.acronym}
                    </Box>
                  </Stack.Item>
                  <Stack.Item grow basis={0} style={{ minWidth: 0 }}>
                    <Box
                      bold
                      fontSize="16px"
                      textAlign="center"
                      color="#f0f5fa"
                      mb={0.75}
                      style={{ overflowWrap: 'anywhere' }}
                    >
                      {faction.name}
                    </Box>
                    <Box
                      color="label"
                      fontSize="12px"
                      lineHeight={1.3}
                      textAlign="center"
                    >
                      {faction.description}
                    </Box>
                  </Stack.Item>
                </Stack>
              </Stack.Item>

              <Stack.Item>
                <Box
                  mb={0.5}
                  bold
                  textAlign="center"
                  color={AFFILIATION_COLORS[affiliation] ?? '#9aa0aa'}
                >
                  {affiliation}
                </Box>
                <Stack justify="center" wrap>
                  {choices.map((choice) => (
                    <Stack.Item key={choice}>
                      <Button
                        compact
                        selected={choice === affiliation}
                        color={choice === affiliation ? undefined : 'transparent'}
                        onClick={() => setAffiliation(faction.id, choice)}
                        style={{
                          borderBottom: `2px solid ${AFFILIATION_COLORS[choice] ?? '#9aa0aa'}`,
                        }}
                      >
                        {choice}
                      </Button>
                    </Stack.Item>
                  ))}
                </Stack>
              </Stack.Item>
            </Stack>
          </Box>
        );
      })}
    </Box>
  );
};
