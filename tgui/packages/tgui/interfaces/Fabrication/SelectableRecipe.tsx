import { useMemo, useState } from 'react';
import {
  Box,
  Button,
  Icon,
  Input,
  LabeledList,
  NoticeBox,
  NumberInput,
  Section,
  Stack,
} from 'tgui-core/components';
import { classes } from 'tgui-core/react';
import { TechWebRecipeIcon } from '../common/TechWebRecipeIcon';
import type {
  Design,
  MaterialChoice,
  MaterialMap,
  MaterialSlot,
} from './Types';

type Props = {
  design: Design;
  available: MaterialMap;
  materialChoices: MaterialChoice[];
  SHEET_MATERIAL_AMOUNT: number;
  onBuild: (materials: Record<string, string>, quantity: number) => void;
  single?: boolean;
  actionLabel?: string;
};

const initialChoice = (slot: MaterialSlot, choices: MaterialChoice[]) => {
  if (
    slot.defaultMaterial &&
    choices.some((choice) => choice.id === slot.defaultMaterial)
  ) {
    return slot.defaultMaterial;
  }
  return slot.optional ? '' : (choices[0]?.id ?? '');
};

// Reference properties belong to the selected *part*, not a weighted average
// of unrelated casing, liner, and conductor materials.
const partProperties = (m: MaterialChoice, role: string) => {
  switch (role) {
    case 'conductor':
    case 'contacts':
    case 'actuator':
      return `Resistivity ${m.resistivity ?? '?'} · ${m.criticalTemperature ? `Superconducts below ${m.criticalTemperature} K, up to ${m.criticalCurrentDensity} A/mm²` : `Conductivity ${m.conductivity}`}`;
    case 'thermal buffer':
      return `Heat capacity ${m.specificHeat ?? '?'} J/(kg·K) · ${m.phaseCapacity ? `${m.phaseCapacity} J phase storage at ${m.phaseTemperature} K` : 'No phase storage'}`;
    case 'insulation':
    case 'grip':
    case 'substrate':
    case 'dielectric':
      return `Thermal isolation ${m.thermalInsulation} · Dielectric strength ${m.dielectricStrength ?? '?'} · Melt ${m.meltingPoint ?? '?'} K`;
    case 'liner':
    case 'jacket':
      return `Corrosion resistance ${m.corrosionResistance} · Melt ${m.meltingPoint ?? '?'} K`;
    case 'working surface':
    case 'barrel':
    case 'bearings':
      return `Hardness ${m.hardness} · Toughness ${m.toughness} · Melt ${m.meltingPoint ?? '?'} K`;
    default:
      return `Strength ${m.integrity} · Density ${m.density} · Melt ${m.meltingPoint ?? '?'} K`;
  }
};

export const ConfigurableRecipeRow = (props: {
  design: Design;
  available: MaterialMap;
  selected?: boolean;
  onSelect: () => void;
}) => {
  const { design, available, selected, onSelect } = props;
  return (
    <div
      className={classes([
        'FabricatorRecipe',
        selected && 'FabricatorRecipe--selected',
      ])}
      onClick={onSelect}
    >
      <div className="FabricatorRecipe__Button FabricatorRecipe__Button--icon">
        <Icon name="sliders-h" />
      </div>
      <TechWebRecipeIcon
        icon={design.icon}
        name={design.name}
        design={design}
        availableMaterials={available}
        canPrint
        action={onSelect}
      />
      <Box color="label" px={1}>
        {design.materialSlots?.length ?? 0} parts
      </Box>
      <Button
        color={selected ? 'good' : 'transparent'}
        icon="chevron-right"
        onClick={onSelect}
      >
        Configure
      </Button>
    </div>
  );
};

/** Persistent standard/custom product workbench shared by every fabricator. */
export const ProductConfigurator = (props: Props) => {
  const { design, available, materialChoices, onBuild, single, actionLabel } =
    props;
  const slots = design.materialSlots ?? [];
  const defaults = useMemo(
    () =>
      Object.fromEntries(
        slots.map((slot) => [slot.role, initialChoice(slot, materialChoices)]),
      ),
    [design.id, materialChoices],
  );
  const [custom, setCustom] = useState(false);
  const [requested, setRequested] = useState<Record<string, string>>(defaults);
  const [activeRole, setActiveRole] = useState(slots[0]?.role ?? '');
  const [search, setSearch] = useState('');
  const [quantity, setQuantity] = useState(1);
  const selected = custom ? requested : defaults;
  const selectedConductor = materialChoices.find(
    (choice) => choice.id === selected.conductor,
  );
  const selectedBuffer = materialChoices.find(
    (choice) => choice.id === selected['thermal buffer'],
  );
  const incompatibleColdAssembly =
    !!selectedConductor?.criticalTemperature &&
    !!selectedBuffer?.phaseTemperature &&
    selectedBuffer.phaseTemperature >= selectedConductor.criticalTemperature;
  const activeSlot = slots.find((slot) => slot.role === activeRole) ?? slots[0];
  const totalCost: MaterialMap = { ...design.cost };
  for (const slot of slots) {
    const materialId = selected[slot.role];
    if (materialId)
      totalCost[materialId] = (totalCost[materialId] ?? 0) + slot.amount;
  }
  const complete = slots.every(
    (slot) => slot.optional || !!selected[slot.role],
  );
  const costEntries = Object.entries(totalCost);
  const maxQuantity =
    complete && costEntries.length
      ? Math.min(
          50,
          ...costEntries.map(([material, amount]) =>
            Math.floor((available[material] ?? 0) / amount),
          ),
        )
      : 0;
  const effectiveMaximum = single ? Math.min(maxQuantity, 1) : maxQuantity;
  const candidates = activeSlot
    ? [...materialChoices]
        .filter((material) =>
          material.label.toLowerCase().includes(search.toLowerCase()),
        )
        .sort((left, right) => left.label.localeCompare(right.label))
    : [];

  return (
    <Section fill scrollable title={design.name}>
      <Box color="label" mb={1}>
        {design.desc}
      </Box>
      <Stack mb={1}>
        <Stack.Item grow>
          <Button
            fluid
            selected={!custom}
            icon="check"
            onClick={() => setCustom(false)}
          >
            Standard
          </Button>
        </Stack.Item>
        <Stack.Item grow>
          <Button
            fluid
            selected={custom}
            icon="sliders-h"
            onClick={() => setCustom(true)}
          >
            Custom
          </Button>
        </Stack.Item>
      </Stack>
      <Section title="Construction" fitted>
        <Stack vertical>
          {slots.map((slot) => {
            const material = materialChoices.find(
              (choice) => choice.id === selected[slot.role],
            );
            return (
              <Stack.Item key={slot.role}>
                <Button
                  fluid
                  selected={custom && activeSlot?.role === slot.role}
                  disabled={!custom}
                  onClick={() => setActiveRole(slot.role)}
                >
                  <Stack align="center">
                    <Stack.Item grow>
                      <Box bold>{slot.label}</Box>
                      <Box color="label" fontSize="11px">
                        {slot.description}
                      </Box>
                    </Stack.Item>
                    <Stack.Item>
                      {material ? (
                        <>
                          <Box
                            inline
                            mr={0.5}
                            style={{
                              background: material.color,
                              border: '1px solid #777',
                              display: 'inline-block',
                              height: '0.8em',
                              width: '0.8em',
                            }}
                          />
                          {material.label}
                        </>
                      ) : (
                        'None'
                      )}
                    </Stack.Item>
                  </Stack>
                </Button>
              </Stack.Item>
            );
          })}
        </Stack>
      </Section>
      {incompatibleColdAssembly && (
        <NoticeBox color="yellow">
          The selected thermal buffer stabilizes above this conductor&apos;s
          critical temperature. It will not keep the conductor superconducting
          without additional cooling.
        </NoticeBox>
      )}
      {custom && activeSlot && (
        <Section title={`Choose ${activeSlot.label}`}>
          <Input
            fluid
            value={search}
            placeholder="Search loaded materials..."
            onChange={setSearch}
            mb={1}
          />
          {activeSlot.optional && (
            <Button
              fluid
              selected={!selected[activeSlot.role]}
              onClick={() =>
                setRequested((previous) => ({
                  ...previous,
                  [activeSlot.role]: '',
                }))
              }
            >
              None
            </Button>
          )}
          <Stack vertical>
            {candidates.map((material) => {
              return (
                <Stack.Item key={material.id}>
                  <Button
                    fluid
                    selected={selected[activeSlot.role] === material.id}
                    onClick={() =>
                      setRequested((previous) => ({
                        ...previous,
                        [activeSlot.role]: material.id,
                      }))
                    }
                  >
                    <Stack align="center">
                      <Stack.Item>
                        <Box
                          style={{
                            background: material.color,
                            border: '1px solid #777',
                            height: '1.2em',
                            width: '1.2em',
                          }}
                        />
                      </Stack.Item>
                      <Stack.Item grow>{material.label}</Stack.Item>
                      <Stack.Item color="label">
                        {material.sheets} sheets
                      </Stack.Item>
                      {material.id === activeSlot.defaultMaterial && (
                        <Stack.Item color="label">Standard</Stack.Item>
                      )}
                    </Stack>
                    <Box color="label" mt={0.5}>
                      {partProperties(material, activeSlot.role)}
                    </Box>
                  </Button>
                </Stack.Item>
              );
            })}
          </Stack>
        </Section>
      )}
      <Section title="Component operating properties">
        <LabeledList>
          {slots.map((slot) => {
            const material = materialChoices.find(
              (choice) => choice.id === selected[slot.role],
            );
            return (
              material && (
                <LabeledList.Item
                  key={slot.role}
                  label={`${slot.label} — ${material.label}`}
                >
                  {partProperties(material, slot.role)}
                </LabeledList.Item>
              )
            );
          })}
        </LabeledList>
        <Box color="label" mt={1}>
          Reference properties at room temperature. Geometry, operating
          temperature, current, and wear determine the finished assembly's
          limits; measure it under load with a multitool.
        </Box>
      </Section>
      {!complete && (
        <NoticeBox danger>Choose every required component.</NoticeBox>
      )}
      {complete && maxQuantity < 1 && (
        <NoticeBox danger>
          Insufficient loaded material for this configuration.
        </NoticeBox>
      )}
      <Stack align="center">
        <Stack.Item grow>
          {!single && (
            <NumberInput
              fluid
              value={Math.min(quantity, Math.max(effectiveMaximum, 1))}
              minValue={1}
              maxValue={Math.max(effectiveMaximum, 1)}
              step={1}
              onChange={(value) => setQuantity(Math.round(value))}
            />
          )}
        </Stack.Item>
        <Stack.Item>
          <Button
            icon="cog"
            color="good"
            disabled={!complete || effectiveMaximum < 1}
            onClick={() =>
              onBuild(
                selected,
                single ? 1 : Math.min(quantity, effectiveMaximum),
              )
            }
          >
            {actionLabel ?? 'Fabricate'}
          </Button>
        </Stack.Item>
      </Stack>
      <Box color="label" mt={0.5} textAlign="right">
        {single
          ? effectiveMaximum
            ? 'Ready to craft'
            : 'Missing materials'
          : `Up to ${effectiveMaximum} available`}
      </Box>
    </Section>
  );
};

export const SelectableRecipe = ProductConfigurator;
