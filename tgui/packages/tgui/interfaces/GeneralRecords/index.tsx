import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import { Section } from 'tgui-core/components';

import { ComplexModal } from '../common/ComplexModal';
import { LoginInfo } from '../common/LoginInfo';
import { LoginScreen } from '../common/LoginScreen';
import { TemporaryNotice } from '../common/TemporaryNotice';
import { DepartmentFinances } from './DepartmentFinances';
import { GeneralRecordsList } from './GeneralRecordsList';
import {
  GeneralRecordsMaintenance,
  GeneralRecordsNavigation,
  GeneralRecordsView,
} from './GeneralRecordsOptions';
import { ManagementContracts } from './ManagementContracts';
import type { Data } from './types';

export const GeneralRecords = (props) => {
  const { data } = useBackend<Data>();
  const { authenticated, screen } = data;
  if (!authenticated) {
    return (
      <Window width={800} height={380}>
        <Window.Content>
          <LoginScreen />
        </Window.Content>
      </Window>
    );
  }

  const body: React.JSX.Element[] = [];
  body[2] = <GeneralRecordsList />;
  body[3] = <GeneralRecordsMaintenance />;
  body[4] = <GeneralRecordsView />;
  body[5] = <DepartmentFinances />;
  body[6] = <ManagementContracts />;

  return (
    <Window width={800} height={640}>
      <ComplexModal />
      <Window.Content className="Layout__content--flexColumn" scrollable>
        <LoginInfo />
        <TemporaryNotice />
        <GeneralRecordsNavigation />
        <Section flexGrow>{(screen && body[screen]) || ''}</Section>
      </Window.Content>
    </Window>
  );
};
