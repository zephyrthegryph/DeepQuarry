import { useBackend } from 'tgui/backend';
import { Section } from 'tgui-core/components';
import type {
  RequestConsoleActions,
  RequestConsoleData,
} from '../generated/RequestConsole';
import { RequestConsoleSendMenu } from './RequestConsoleSend';

export const RequestConsoleSupplies = (props) => {
  const { data } = useBackend<RequestConsoleData, RequestConsoleActions>();
  const { department, supply_dept } = data;
  return (
    <Section title="Supplies">
      <RequestConsoleSendMenu dept_list={supply_dept} department={department} />
    </Section>
  );
};

export const RequestConsoleAssistance = (props) => {
  const { data } = useBackend<RequestConsoleData, RequestConsoleActions>();
  const { department, assist_dept } = data;
  return (
    <Section title="Request assistance from another department">
      <RequestConsoleSendMenu dept_list={assist_dept} department={department} />
    </Section>
  );
};

export const RequestConsoleRelay = (props) => {
  const { data } = useBackend<RequestConsoleData, RequestConsoleActions>();
  const { department, info_dept } = data;
  return (
    <Section title="Report Anonymous Information">
      <RequestConsoleSendMenu dept_list={info_dept} department={department} />
    </Section>
  );
};
