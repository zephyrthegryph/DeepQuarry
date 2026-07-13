import { useState } from 'react';
import { Box, Button, Dropdown, Icon, Tooltip } from 'tgui-core/components';
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

  // Build collision-safe option strings mapped back to material ids.
  const options: string[] = [];
  const labelToId: Record<string, string> = {};
  for (let index = 0; index < materialChoices.length; index++) {
    const choice = materialChoices[index];
    let label = `${choice.label} (${choice.sheets})`;
    if (labelToId[label] !== undefined) {
      label = `${label} #${index}`;
    }
    labelToId[label] = choice.id;
    options.push(label);
  }

  const [selectedLabel, setSelectedLabel] = useState(options[0] ?? '');
  const selectedId = labelToId[selectedLabel] ?? '';
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
      <div style={{ display: 'flex', alignItems: 'center', padding: '0 4px' }}>
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
  );
};
