import { useBackend } from 'tgui/backend';
import { Box, Button, LabeledList, Section } from 'tgui-core/components';

import { modalOpen } from '../../interfaces/common/ComplexModal';
import { doEdit } from '../GeneralRecords/functions';
import type { SecurityRecordsActions } from '../generated/SecurityRecords';
import type { Data } from './types';
import { Label } from 'tgui/components/Label';

export const SecurityRecordsViewSecurity = (props) => {
  const { act, data } = useBackend<Data, SecurityRecordsActions>();
  const { security } = data;
  if (!security?.fields) {
    return (
      <Box color="bad">
        Security records lost!
        <Button icon="pen" ml="0.5rem" onClick={() => act('new')}>
          New Record
        </Button>
      </Box>
    );
  }
  return (
    <>
      <LabeledList>
        {security.fields.map((field, i) => (
          <LabeledList.Item key={i} label={field.field}>
            <Box preserveWhitespace>
              {field.value}
              {!!field.edit &&
                (field.edit === 'notes' ? (
                  <Button
                    icon="pen"
                    ml="1rem"
                    onClick={() => act('edit_notes')}
                  />
                ) : (
                  <Button
                    icon="pen"
                    ml="0.5rem"
                    mb={'initial'}
                    onClick={() => doEdit(field)}
                  />
                ))}
            </Box>
          </LabeledList.Item>
        ))}
      </LabeledList>
      <Section title="Comments/Log">
        {security.comments && security.comments.length === 0 ? (
          <Label>No comments found.</Label>
        ) : (
          security.comments?.map((comment, i) => (
            <Box key={i}>
              <Label inline>{comment.header}</Label>
              <br />
              {comment.text}
              <Button
                icon="comment-slash"
                color="bad"
                ml="0.5rem"
                onClick={() => act('del_c', { del_c: i + 1 })}
              />
            </Box>
          ))
        )}

        <Button
          icon="comment"
          color="good"
          mt="0.5rem"
          mb="0"
          onClick={() => modalOpen('add_c')}
        >
          Add Entry
        </Button>
      </Section>
    </>
  );
};
