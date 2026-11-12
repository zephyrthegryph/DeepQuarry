import { useBackend } from 'tgui/backend';
import type { SleeperActions, SleeperData } from '../generated/Sleeper';
import { SleeperChemicals } from './SleeperChemicals';
import { SleeperDiagnosis } from './SleeperDiagnosis';
import { SleeperDialysisPump } from './SleeperDialysisPump';
import { SleeperOccupant } from './SleeperOccupant';

export const SleeperMain = (props) => {
  const { data } = useBackend<SleeperData, SleeperActions>();
  const { dialysis, stomachpumping } = data;
  return (
    <>
      <SleeperOccupant />
      <SleeperDiagnosis />
      <SleeperDialysisPump
        title="Dialysis"
        active={dialysis}
        actToDo="togglefilter"
      />
      <SleeperDialysisPump
        title="Stomach Pump"
        active={stomachpumping}
        actToDo="togglepump"
      />
      <SleeperChemicals />
    </>
  );
};
