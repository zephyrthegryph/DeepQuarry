import { useBackend } from 'tgui/backend';
import { Button, NoticeBox, Stack } from 'tgui-core/components';

export const FunForYouTab = (props) => {
  const { act } = useBackend();
  return (
    <Stack fill vertical>
      <Stack.Item>
        <Stack>
          <Stack.Item>
            {/*
            <NoticeBox danger mb={0} width={19.6}>
            </NoticeBox>
            */}
            <NoticeBox width={19.6} mb={0}>
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
            <NoticeBox danger width={19.6} mb={0}>
            </NoticeBox>
            */}
            <NoticeBox width={19.6} mb={0}>
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack>
          <Stack.Item>
            {/*
            <NoticeBox danger mb={0} width={19.6}>
            </NoticeBox>
            */}
            <NoticeBox danger mb={0} width={19.6}>
              <Button
                color="red"
                icon="paw"
                fluid
                onClick={() => act('corgie')}
              >
                Change everyone to corgies
              </Button>
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            <NoticeBox danger width={19.6} mb={0}>
              <Button
                color="red"
                icon="paw"
                fluid
                onClick={() => act('monkey')}
              >
                Change everyone to monkeys
              </Button>
            </NoticeBox>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        {/*
        <NoticeBox danger mb={0}>
        </NoticeBox>
        */}
        <NoticeBox mb={0}>Your admin button here, coder!</NoticeBox>
      </Stack.Item>
      <Stack.Item>
        <NoticeBox danger mb={0}>
          {/*
           */}
          <Button
            color="black"
            icon="fire"
            fluid
            onClick={() => act('supermatter_cascade')}
          >
            Supermatter Cascade! (DANGEROUS: ends round, also big boom)
          </Button>
        </NoticeBox>
      </Stack.Item>
      <Stack.Item>
        <Stack fill>
          <Stack.Item>
            {/*
            <NoticeBox danger width={19.6} mb={0}>
            </NoticeBox>
            */}
            <NoticeBox width={19.6} mb={0}>
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
            <NoticeBox info width={19.6} mb={0}>
            </NoticeBox>
            */}
            <NoticeBox width={19.6} mb={0}>
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        <Stack>
          <Stack.Item>
            {/*
            <NoticeBox danger width={19.6} mb={0}>
            </NoticeBox>
            */}
            <NoticeBox width={19.6} mb={0}>
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            {/*
            <NoticeBox info width={19.6} mb={0}>
            </NoticeBox>
            */}
            <NoticeBox width={19.6} mb={0}>
              Your admin button here, coder!
            </NoticeBox>
          </Stack.Item>
        </Stack>
      </Stack.Item>
      <Stack.Item>
        {/*
        <Stack fill>
          <Stack.Item>
            <NoticeBox danger width={19.6} mb={0}>
            </NoticeBox>
          </Stack.Item>
          <Stack.Item>
            <NoticeBox info width={19.6} mb={0}>
            </NoticeBox>
          </Stack.Item>
        </Stack>
        */}
        <Stack.Item>
          <NoticeBox danger mb={0}>
            <Button
              color="black"
              icon="fire"
              fluid
              onClick={() => act('summon_narsie')}
            >
              Summon Nar-Sie! (DANGEROUS: ends round)
            </Button>
          </NoticeBox>
        </Stack.Item>
      </Stack.Item>
      <Stack>
        <Stack.Item>
          <NoticeBox width={19.6} mb={0}>
            Your admin button here, coder!
          </NoticeBox>
        </Stack.Item>
        <Stack.Item>
          <NoticeBox width={19.6} mb={0}>
            Your admin button here, coder!
          </NoticeBox>
        </Stack.Item>
      </Stack>
    </Stack>
  );
};
