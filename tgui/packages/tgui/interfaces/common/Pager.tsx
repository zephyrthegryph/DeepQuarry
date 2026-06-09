import { Box, Button } from 'tgui-core/components';

type Props = {
  page: number;
  total: number;
  onPrev: () => void;
  onNext: () => void;
  disabled?: boolean;
};

export const Pager = (props: Props) => {
  const { page, total, onPrev, onNext, disabled } = props;
  return (
    <Box>
      <Button
        icon="arrow-left"
        disabled={disabled || page <= 1}
        onClick={onPrev}
      />
      <Box inline mx={1}>
        Page {page} of {total}
      </Box>
      <Button
        icon="arrow-right"
        disabled={disabled || page >= total}
        onClick={onNext}
      />
    </Box>
  );
};
