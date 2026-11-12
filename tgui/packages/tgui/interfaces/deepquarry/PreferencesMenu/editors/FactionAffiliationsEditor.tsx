import { useBackend } from 'tgui/backend';
import { Box, Button, Stack } from 'tgui-core/components';
import type { EditorProps } from './index';
import { Label } from 'tgui/components/Label';

const AFFILIATION_COLORS: Record<string, string> = {
  Hostile: '#d94b4b',
  Opposed: '#d8894b',
  Neutral: '#9aa0aa',
  Friendly: '#58a7d8',
  Member: '#62c48d',
};

export const FactionAffiliationsEditor = ({
  data,
  staticData,
}: EditorProps<'faction_affiliations'>) => {
  const { act } = useBackend();
  const { affiliations } = data;
  const { factions = [], choices = [] } = staticData ?? {};

  const setAffiliation = (faction: string, affiliation: string) =>
    act('dq_editor_action', {
      editor: 'faction_affiliations',
      action: 'set_affiliation',
      params: { faction, affiliation },
    });

  if (!factions.length) {
    return <Label p={2}>Loading faction registry...</Label>;
  }

  return (
    <Box
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
        gridTemplateRows: 'repeat(3, minmax(0, 1fr))',
        gap: '0.667em',
        width: '100%',
        height: '100%',
        minWidth: 0,
        minHeight: 0,
        padding: '0.667em',
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
              borderTop: `0.333em solid ${faction.color}`,
              borderRadius: '0.417em',
              background: `linear-gradient(145deg, ${faction.color}22, rgba(24,30,39,.98) 48%)`,
            }}
          >
            <Stack fill vertical>
              <Stack.Item grow basis={0} style={{ minHeight: 0 }}>
                <Stack fill align="center">
                  <Stack.Item>
                    <Box
                      style={{
                        width: '4.833em',
                        height: '4.833em',
                        borderRadius: '0.75em',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        background: `${faction.color}cc`,
                        border: '1px solid rgba(255,255,255,.25)',
                        color: '#fff',
                        fontWeight: 800,
                        fontSize:
                          faction.acronym.length > 4 ? '0.833em' : '1.25em',
                        boxShadow: `0 0 1em ${faction.color}33`,
                      }}
                    >
                      {faction.acronym}
                    </Box>
                  </Stack.Item>
                  <Stack.Item grow basis={0} style={{ minWidth: 0 }}>
                    <Box
                      bold
                      fontSize="1.333em"
                      textAlign="center"
                      color="#f0f5fa"
                      mb={0.75}
                      style={{ overflowWrap: 'anywhere' }}
                    >
                      {faction.name}
                    </Box>
                    <Label fontSize="1em" lineHeight={1.3} textAlign="center">
                      {faction.description}
                    </Label>
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
                        color={
                          choice === affiliation ? undefined : 'transparent'
                        }
                        onClick={() => setAffiliation(faction.id, choice)}
                        style={{
                          borderBottom: `0.167em solid ${AFFILIATION_COLORS[choice] ?? '#9aa0aa'}`,
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
