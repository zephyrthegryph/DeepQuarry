import { Box } from 'tgui-core/components';

type Props = {
  value: unknown;
  yes?: string;
  no?: string;
};

/** A state word coloured by its truth: good when set, bad when not. */
export function YesNo(props: Props) {
  const { value, yes = 'Yes', no = 'No' } = props;
  return <Box color={value ? 'good' : 'bad'}>{value ? yes : no}</Box>;
}
