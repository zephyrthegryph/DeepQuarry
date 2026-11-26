import { useBackend } from 'tgui/backend';
import { Button, NoticeBox, Stack } from 'tgui-core/components';

import { buttonWidthNormal, lineHeightNormal } from '../constants';

export const FunTab = (props) => {
  const { act } = useBackend();
  return (
    <Stack fill vertical>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            {/*
             */}
            <Button
              icon="ghost"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('ghost_mode')}
            >
              Ghost Mode
            </Button>
          </Stack.Item>
          <Stack.Item>
            {/*
             */}
            <Button
              icon="palette"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('paintball_mode')}
            >
              Paintball Mode
            </Button>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            <Button
              icon="bolt"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('power')}
            >
              All areas powered
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="moon"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('unpower')}
            >
              All areas unpowered
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="plug"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('quickpower')}
            >
              recharge SMESs
            </Button>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            {/*
             */}
            <Button
              icon="power-off"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('gravity')}
            >
              Toggle Station Gravity
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="robot"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('tripleAI')}
            >
              Triple AI mode
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="bullhorn"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('onlyone')}
            >
              THERE CAN ONLY BE-
            </Button>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            {/*
             */}
            <NoticeBox
              mb={-0.5}
              width={buttonWidthNormal}
              height={lineHeightNormal}
            >
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="bomb"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('changebombcap')}
            >
              Change Bomb Cap
            </Button>
          </Stack.Item>
          <Stack.Item>
            {/*
             */}
            <Button
              icon="pencil"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('alter_narsie')}
            >
              Alter Nar-Sie
            </Button>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            <Button
              icon="shirt"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('remove_all_clothing')}
            >
              Remove ALL Clothing
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="shirt"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('remove_internal_clothing')}
            >
              Rem. &apos;internal&apos; Cloth.
            </Button>
          </Stack.Item>
          <Stack.Item>
            <Button
              icon="person-rifle"
              lineHeight={lineHeightNormal}
              width={buttonWidthNormal}
              onClick={() => act('send_strike_team')}
            >
              Send Strike Team
            </Button>
          </Stack.Item>
        </Stack>
      </Stack.Item>
    </Stack>
  );
};
