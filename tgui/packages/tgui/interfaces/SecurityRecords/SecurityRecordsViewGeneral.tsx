import { useBackend } from 'tgui/backend';
import { Box, Button, Image, LabeledList, Stack } from 'tgui-core/components';

import { doEdit } from '../GeneralRecords/functions';
import type { SecurityRecordsActions } from '../generated/SecurityRecords';
import type { Data } from './types';
import { Label } from 'tgui/components/Label';

export const SecurityRecordsViewGeneral = (props) => {
  const { act, data } = useBackend<Data, SecurityRecordsActions>();
  const { general } = data;
  if (!general?.fields) {
    return <Box color="bad">General records lost!</Box>;
  }
  return (
    <Stack>
      <Stack.Item>
        <LabeledList>
          {general.fields.map((field, i) => (
            <LabeledList.Item key={i} label={field.field}>
              <Box height="20px" inline preserveWhitespace>
                {field.value}
                {!!field.edit && (
                  <Button
                    icon="pen"
                    ml="0.5rem"
                    onClick={() => doEdit(field)}
                  />
                )}
              </Box>
            </LabeledList.Item>
          ))}
        </LabeledList>
      </Stack.Item>
      <Stack.Item textAlign="right">
        {!!general.has_photos &&
          general.photos!.map((p, i) => (
            <Label key={i} inline textAlign="center">
              <Image
                src={p.substring(1, p.length - 1)}
                style={{
                  width: '96px',
                  marginBottom: '0.5rem',
                }}
              />
              <br />
              Photo #{i + 1}
            </Label>
          ))}
        <Box>
          <Button onClick={() => act('photo_front')}>Update Front Photo</Button>
          <Button onClick={() => act('photo_side')}>Update Side Photo</Button>
        </Box>
      </Stack.Item>
    </Stack>
  );
};
