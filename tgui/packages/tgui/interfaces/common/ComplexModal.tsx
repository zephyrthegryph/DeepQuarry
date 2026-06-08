import { type KeyboardEvent, useEffect, useState } from 'react';
import { useBackend } from 'tgui/backend';
import { sendAct } from 'tgui/events/act';
import { backendStateAtom, store } from 'tgui/events/store';
import {
  Box,
  Button,
  Dropdown,
  Image,
  Input,
  Modal,
  Stack,
} from 'tgui-core/components';

type ModalData<TArgs = Record<string, unknown>> = {
  id: string;
  args: TArgs;
  text: string;
  type: string;
};

type Data<TArgs = Record<string, unknown>> = {
  modal: ModalData<TArgs> | null;
};
const bodyOverrides = {};

/**
 * Registers an override for any modal with the given id.
 * The override function is called with the modal data and returns JSX.
 * It is invoked inside the ComplexModal component's render, so hooks are valid.
 */

type ModalOverrideData<TArgs = Record<string, unknown>> = {
  id: string;
  text: string;
  args: TArgs;
  type: string;
};

export const modalRegisterBodyOverride = (
  id: string,
  bodyOverride: (modal: ModalOverrideData) => React.JSX.Element,
) => {
  bodyOverrides[id] = bodyOverride;
};

type ExtendedModalData<TArgs = Record<string, unknown>> = ModalData<TArgs> &
  Partial<{
    value: string;
    choices: string[];
    no_text: string;
    yes_text: string;
  }>;

type ComplexData<TArgs = Record<string, unknown>> = {
  modal: ExtendedModalData<TArgs> | null;
};

/** Internal act type — short-hand for the tgui act callback. */
type ActFn = (action: string, params?: Record<string, unknown>) => void;

/** Reads the current modal from the global jotai store synchronously. */
const currentModal = (): ModalData | null => {
  const state = store.get(backendStateAtom);
  return (state.data as Data).modal ?? null;
};

/**
 * Pure helpers that operate on already-resolved act/modal values.
 * These are plain functions with no hook calls — safe to use in event handlers.
 */
const doModalOpen = (
  act: ActFn,
  modal: ModalData | null,
  id: string,
  args: Record<string, unknown> = {},
) => {
  const newArgs = Object.assign(modal ? modal.args : {}, args);
  act('modal_open', {
    id: id,
    arguments: JSON.stringify(newArgs),
  });
};

const doModalAnswer = (
  act: ActFn,
  modal: ExtendedModalData | null,
  id: string,
  answer: string | undefined,
  args: Record<string, unknown>,
) => {
  if (!modal) {
    return;
  }
  const newArgs = Object.assign(modal.args || {}, args || {});
  act('modal_answer', {
    id: id,
    answer: answer,
    arguments: JSON.stringify(newArgs),
  });
};

const doModalClose = (act: ActFn, id: string | null) => {
  act('modal_close', { id: id });
};

/**
 * Displays a modal and its actions. Passed data must have a valid modal field.
 *
 * **A valid modal field contains:**
 *
 * `id` — The identifier of the modal.
 * Used for server-client communication and overriding
 *
 * `text` — The text of the modal
 *
 * `type` — The type of the modal:
 * `message`, `input`, `choice`, `bento` and `boolean`.
 * Overriden by a body override registered to the identifier if applicable.
 * Defaults to `message` if not found
 * @param {object} props
 */
export const ComplexModal = (props: {
  maxWidth?: string;
  maxHeight?: string;
}) => {
  const { act, data } = useBackend<ComplexData>();

  const { modal } = data;

  const [curValue, setCurValue] = useState(String(modal?.value ?? ''));

  useEffect(() => {
    if (modal?.type === 'input') {
      setCurValue(String(modal.value ?? ''));
    }
  }, [modal?.value, modal?.type]);

  if (!modal) {
    return null;
  }

  const { id, text, type } = modal;

  const modalOnEscape:
    | ((e: KeyboardEvent<HTMLDivElement>) => void)
    | undefined = (_e) => doModalClose(act, id);
  let modalOnEnter: ((e: KeyboardEvent<HTMLDivElement>) => void) | undefined;
  let modalBody: React.JSX.Element | undefined;
  let modalFooter: React.JSX.Element = (
    <Button
      icon="arrow-left"
      color="grey"
      onClick={() => doModalClose(act, null)}
    >
      Cancel
    </Button>
  );

  // Different contents depending on the type
  if (bodyOverrides[id]) {
    modalBody = bodyOverrides[id](modal);
  } else if (type === 'input') {
    modalOnEnter = (_e) => doModalAnswer(act, modal, id, curValue, {});
    modalBody = (
      <Input
        key={id}
        value={curValue}
        placeholder="ENTER to submit"
        width="100%"
        my="0.5rem"
        autoFocus
        autoSelect
        onChange={(val) => {
          setCurValue(val);
        }}
      />
    );
    modalFooter = (
      <Box mt="0.5rem">
        <Button
          icon="arrow-left"
          color="grey"
          onClick={() => doModalClose(act, null)}
        >
          Cancel
        </Button>
        <Button
          icon="check"
          color="good"
          style={{
            float: 'right',
          }}
          m="0"
          onClick={() => doModalAnswer(act, modal, id, curValue, {})}
        >
          Confirm
        </Button>
        <Box
          style={{
            clear: 'both',
          }}
        />
      </Box>
    );
  } else if (type === 'choice') {
    const { choices = [] } = modal;
    const realChoices =
      typeof modal.choices === 'object' ? Object.values(choices) : choices;
    modalBody = (
      <Dropdown
        autoScroll={false}
        options={realChoices}
        selected={modal.value}
        width="100%"
        my="0.5rem"
        onSelected={(val) => doModalAnswer(act, modal, id, val, {})}
      />
    );
  } else if (type === 'bento') {
    const { choices = [], value = '' } = modal;
    modalBody = (
      <Stack wrap="wrap" my="0.5rem" maxHeight="1%">
        {choices.map((c, i) => (
          <Stack.Item key={i}>
            <Button
              selected={i + 1 === parseInt(value, 10)}
              onClick={() =>
                doModalAnswer(act, modal, id, (i + 1).toString(), {})
              }
            >
              <Image src={c} />
            </Button>
          </Stack.Item>
        ))}
      </Stack>
    );
  } else if (type === 'bentospritesheet') {
    const { choices = [], value = '' } = modal;
    modalBody = (
      <Stack wrap="wrap" my="0.5rem" maxHeight="1%">
        {choices.map((c, i) => (
          <Stack.Item key={i}>
            <Button
              selected={i + 1 === parseInt(value, 10)}
              onClick={() =>
                doModalAnswer(act, modal, id, (i + 1).toString(), {})
              }
            >
              <Box className={c} />
            </Button>
          </Stack.Item>
        ))}
      </Stack>
    );
  } else if (type === 'boolean') {
    modalFooter = (
      <Box mt="0.5rem">
        <Button
          icon="times"
          color="bad"
          style={{
            float: 'left',
          }}
          mb="0"
          onClick={() => doModalAnswer(act, modal, id, '0', {})}
        >
          {modal.no_text}
        </Button>
        <Button
          icon="check"
          color="good"
          style={{
            float: 'right',
          }}
          m="0"
          onClick={() => doModalAnswer(act, modal, id, '1', {})}
        >
          {modal.yes_text}
        </Button>
        <Box
          style={{
            clear: 'both',
          }}
        />
      </Box>
    );
  }

  return (
    <Modal
      maxWidth={props.maxWidth || `${window.innerWidth / 2}px`}
      maxHeight={props.maxHeight || `${window.innerHeight / 2}px`}
      onEnter={modalOnEnter}
      onEscape={modalOnEscape}
      mx="auto"
    >
      <Box inline>{text}</Box>
      {modalBody}
      {modalFooter}
    </Modal>
  );
};

/**
 * Sends a call to BYOND to open a modal.
 * Reads act/modal from the global jotai store synchronously — no hook call.
 * Safe to call from event handlers and outside React render.
 */
export const modalOpen = (id: string, args: Record<string, unknown> = {}) => {
  doModalOpen(sendAct, currentModal(), id, args);
};
