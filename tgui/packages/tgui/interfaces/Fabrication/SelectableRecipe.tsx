import { useState } from 'react';
import {
  Box,
  Button,
  Dropdown,
  Icon,
  ProgressBar,
  Stack,
  Tooltip,
} from 'tgui-core/components';
import { classes } from 'tgui-core/react';
import { TechWebRecipeIcon } from '../common/TechWebRecipeIcon';
import type { Design, MaterialChoice, MaterialMap } from './Types';

type Props = {
  design: Design;
  available: MaterialMap;
  materialChoices: MaterialChoice[];
  SHEET_MATERIAL_AMOUNT: number;
  /** Fires a build of `quantity` units from the chosen material id. */
  onBuild: (materialId: string, quantity: number) => void;
};

/**
 * A recipe row whose material is chosen from the loaded materials at print time.
 * Shared by the protolathe (Fabricator) and the autolathe — each passes its own
 * `onBuild` so the underlying build action differs while the row looks identical.
 */
export const SelectableRecipe = (props: Props) => {
  const { design, available, materialChoices, SHEET_MATERIAL_AMOUNT, onBuild } =
    props;

  // Registry ids are globally unique. Labels carry a short id suffix only when
  // two independently processed stocks happen to have the same display name.
  const options: string[] = [];
  const labelToId: Record<string, string> = {};
  for (let index = 0; index < materialChoices.length; index++) {
    const choice = materialChoices[index];
    let label = `${choice.label} (${choice.sheets})`;
    if (labelToId[label] !== undefined) {
      label = `${label} · ${choice.id.slice(-6)}`;
    }
    labelToId[label] = choice.id;
    options.push(label);
  }

  const [selectedLabel, setSelectedLabel] = useState(options[0] ?? '');
  const selectedId = labelToId[selectedLabel] ?? '';
  const selected = materialChoices.find((choice) => choice.id === selectedId);
  const hasMaterial = selectedId !== '';

  const perItem = design.selectableAmount ?? 0;
  const availableUnits = hasMaterial ? (available[selectedId] ?? 0) : 0;
  const maxMult =
    perItem > 0 ? Math.min(Math.floor(availableUnits / perItem), 50) : 0;

  const costLabel = (quantity: number) =>
    `Uses ${((perItem * quantity) / SHEET_MATERIAL_AMOUNT).toFixed(2)} sheet(s)`;

  const QuantityButton = (qprops: { quantity: number }) => {
    const enabled = hasMaterial && maxMult >= qprops.quantity;
    return (
      <Tooltip
        content={hasMaterial ? costLabel(qprops.quantity) : 'Select a material'}
      >
        <div
          className={classes([
            'FabricatorRecipe__Button',
            !enabled && 'FabricatorRecipe__Button--disabled',
          ])}
          onClick={() => enabled && onBuild(selectedId, qprops.quantity)}
        >
          &times;{qprops.quantity}
        </div>
      </Tooltip>
    );
  };

  return (
    <div>
      <div className="FabricatorRecipe">
        <Tooltip content={design.desc} position="right">
          <div
            className={classes([
              'FabricatorRecipe__Button',
              'FabricatorRecipe__Button--icon',
              !hasMaterial && 'FabricatorRecipe__Button--disabled',
            ])}
          >
            <Icon name="layer-group" />
          </div>
        </Tooltip>
        <TechWebRecipeIcon
          icon={design.icon}
          name={design.name}
          design={design}
          availableMaterials={available}
          canPrint={hasMaterial && maxMult >= 1}
          action={() => hasMaterial && maxMult >= 1 && onBuild(selectedId, 1)}
        />
        <div
          style={{ display: 'flex', alignItems: 'center', padding: '0 4px' }}
        >
          {options.length === 0 ? (
            <Box color="bad">No material</Box>
          ) : (
            <Dropdown
              width="11em"
              selected={selectedLabel}
              options={options}
              onSelected={(value) => setSelectedLabel(value)}
            />
          )}
        </div>
        <QuantityButton quantity={5} />
        <QuantityButton quantity={10} />
        <div
          className={classes([
            'FabricatorRecipe__Button',
            !hasMaterial && 'FabricatorRecipe__Button--disabled',
          ])}
        >
          <Button.Input
            color="transparent"
            buttonText={`[Max: ${maxMult}]`}
            onCommit={(value) =>
              hasMaterial && onBuild(selectedId, Number(value))
            }
          />
        </div>
      </div>
      {selected && (
        <Box backgroundColor="rgba(0, 0, 0, 0.25)" p={0.5} mb={0.5} ml={5}>
          {!!selected.layers.length && (
            <Stack mb={0.5} wrap>
              {selected.layers.map((layer) => (
                <Stack.Item key={layer.role}>
                  <Box inline color="label">
                    {layer.role}:
                  </Box>{' '}
                  {layer.name} ({layer.share}%)
                </Stack.Item>
              ))}
            </Stack>
          )}
          <Stack>
            {[
              ['Hardness', selected.hardness],
              ['Toughness', selected.toughness],
              ['Conductivity', selected.conductivity],
              ['Heat', selected.heatResistance],
              ['Corrosion', selected.corrosionResistance],
            ].map(([name, value]) => (
              <Stack.Item grow key={String(name)}>
                <Box color="label" fontSize="10px">
                  {name}
                </Box>
                <ProgressBar
                  value={Number(value)}
                  minValue={0}
                  maxValue={100}
                  color="good"
                />
              </Stack.Item>
            ))}
          </Stack>
          <Box mt={0.5} color="label">
            Pressure geometry: {selected.pressureLimit} atm
            {selected.responses.length > 0 &&
              ` · ${selected.responses.join(' · ')}`}
          </Box>
        </Box>
      )}
    </div>
  );
};
