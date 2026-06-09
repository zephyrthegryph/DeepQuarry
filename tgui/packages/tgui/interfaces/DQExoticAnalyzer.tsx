// DQ Exotic Material Analyzer.
//
// Left pane: the currently-loaded sample. Right pane: the catalogue of
// materials scanned at this machine. Scanning the loaded sample reveals
// the 11 core stats grouped by category plus any behavior components,
// and adds the material to the catalogue.

import { useState } from 'react';
import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  LabeledList,
  NoticeBox,
  Section,
  Stack,
} from 'tgui-core/components';

type Stat = {
  name: string;
  magnitude: number;
  debuff?: boolean;
};

type Trait = {
  name: string;
  description: string;
  debuff: boolean;
};

type Material = {
  id: number;
  name: string;
  color: string;
  band: number;
  rarity: number;
  material_class: string;
  scanned: boolean;
  mechanical: Stat[];
  thermal: Stat[];
  electrical: Stat[];
  chemical: Stat[];
  behaviors: Stat[];
  traits: Trait[];
};

type Data = {
  loaded: Material | null;
  catalogue: Material[];
};

const RARITY_LABEL = ['', 'Common', 'Uncommon', 'Rare'];

const formatNum = (n: number): string => `${Math.round(n * 10) / 10}`;

const Swatch = (props: { color: string; size?: number }) => (
  <Box
    inline
    width={`${props.size ?? 14}px`}
    height={`${props.size ?? 14}px`}
    backgroundColor={props.color}
    style={{
      border: '1px solid #444',
      borderRadius: '2px',
      verticalAlign: 'middle',
      marginRight: '6px',
    }}
  />
);

const StatRow = (props: { stat: Stat }) => (
  <LabeledList.Item
    label={props.stat.name}
    color={props.stat.debuff ? 'bad' : undefined}
  >
    <Box inline bold>
      {formatNum(props.stat.magnitude)}
    </Box>
  </LabeledList.Item>
);

const StatGroup = (props: { title: string; stats: Stat[] }) => {
  if (!props.stats || props.stats.length === 0) {
    return null;
  }
  return (
    <Section title={props.title}>
      <LabeledList>
        {props.stats.map((s) => (
          <StatRow key={s.name} stat={s} />
        ))}
      </LabeledList>
    </Section>
  );
};

const TraitGroup = (props: { traits: Trait[] }) => {
  if (!props.traits || props.traits.length === 0) {
    return null;
  }
  return (
    <Section title="Traits">
      <LabeledList>
        {props.traits.map((t) => (
          <LabeledList.Item
            key={t.name}
            label={t.name}
            color={t.debuff ? 'bad' : 'good'}
          >
            <Box inline color="label">
              {t.description}
            </Box>
          </LabeledList.Item>
        ))}
      </LabeledList>
    </Section>
  );
};

const MaterialDetail = (props: { material: Material }) => {
  const { material } = props;
  return (
    <>
      <StatGroup title="Mechanical" stats={material.mechanical} />
      <StatGroup title="Thermal" stats={material.thermal} />
      <StatGroup title="Electrical / Magnetic" stats={material.electrical} />
      <StatGroup title="Chemical" stats={material.chemical} />
      {material.behaviors && material.behaviors.length > 0 && (
        <StatGroup title="Behaviors" stats={material.behaviors} />
      )}
      <TraitGroup traits={material.traits} />
    </>
  );
};

const LoadedPane = () => {
  const { act, data } = useBackend<Data>();
  const { loaded } = data;

  if (!loaded) {
    return (
      <Section fill title="Sample Tray">
        <NoticeBox>
          No sample loaded. Insert an exotic material sample to begin
          analysis.
        </NoticeBox>
      </Section>
    );
  }

  return (
    <Section
      fill
      scrollable
      title={
        <>
          <Swatch color={loaded.color} />
          {loaded.name}
        </>
      }
      buttons={
        <>
          <Button
            icon="search"
            color={loaded.scanned ? 'transparent' : 'good'}
            disabled={loaded.id === 0}
            onClick={() => act('scan')}
          >
            {loaded.scanned ? 'Re-scan' : 'Analyze'}
          </Button>
          <Button icon="eject" onClick={() => act('eject')}>
            Eject
          </Button>
        </>
      }
    >
      <LabeledList>
        <LabeledList.Item label="Class">
          {loaded.material_class || 'Unknown'}
        </LabeledList.Item>
        <LabeledList.Item label="Depth Band">
          Band {loaded.band} (depths {(loaded.band - 1) * 5 + 1}-
          {loaded.band * 5})
        </LabeledList.Item>
        <LabeledList.Item label="Rarity">
          {RARITY_LABEL[loaded.rarity] || 'Unknown'}
        </LabeledList.Item>
      </LabeledList>
      <Box mt={2}>
        {loaded.scanned ? (
          <MaterialDetail material={loaded} />
        ) : (
          <NoticeBox info>
            Properties have not been analyzed. Press <b>Analyze</b> to read
            the full profile.
          </NoticeBox>
        )}
      </Box>
    </Section>
  );
};

const CataloguePane = () => {
  const { data } = useBackend<Data>();
  const { catalogue } = data;
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const selected =
    catalogue.find((m) => m.id === selectedId) || catalogue[0] || null;

  return (
    <Section fill scrollable title={`Catalogue (${catalogue.length})`}>
      {catalogue.length === 0 ? (
        <Box color="label">
          No materials have been analyzed at this terminal yet.
        </Box>
      ) : (
        <Stack vertical fill>
          <Stack.Item>
            <Stack wrap>
              {catalogue.map((m) => (
                <Stack.Item key={m.id} mr={1} mb={1}>
                  <Button
                    selected={selected?.id === m.id}
                    onClick={() => setSelectedId(m.id)}
                  >
                    <Swatch color={m.color} />
                    {m.name}
                  </Button>
                </Stack.Item>
              ))}
            </Stack>
          </Stack.Item>
          {selected && (
            <Stack.Item grow>
              <Section
                title={
                  <>
                    <Swatch color={selected.color} />
                    {selected.name} — {selected.material_class} (
                    {RARITY_LABEL[selected.rarity]})
                  </>
                }
              >
                <MaterialDetail material={selected} />
              </Section>
            </Stack.Item>
          )}
        </Stack>
      )}
    </Section>
  );
};

export const DQExoticAnalyzer = () => {
  return (
    <Window width={950} height={650}>
      <Window.Content>
        <Stack fill>
          <Stack.Item basis="45%">
            <LoadedPane />
          </Stack.Item>
          <Stack.Item grow>
            <CataloguePane />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
