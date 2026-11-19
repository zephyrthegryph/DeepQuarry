import { useBackend } from 'tgui/backend';
import { Box, Button, NoticeBox, Stack } from 'tgui-core/components';

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
            {/* An unused slot: kept empty so the grid stays aligned. */}
            <Box width={19.6} mb={0} />
          </Stack.Item>
          <Stack.Item>
            {/*
            <NoticeBox danger width={19.6} mb={0}>
            </NoticeBox>
            */}
            {/* An unused slot: kept empty so the grid stays aligned. */}
            <Box width={19.6} mb={0} />
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
        {/* An unused slot: kept empty so the grid stays aligned. */}
        <Box mb={0} />
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
            {/* An unused slot: kept empty so the grid stays aligned. */}
            <Box width={19.6} mb={0} />
          </Stack.Item>
          <Stack.Item>
            {/*
            <NoticeBox info width={19.6} mb={0}>
            </NoticeBox>
            */}
            {/* An unused slot: kept empty so the grid stays aligned. */}
            <Box width={19.6} mb={0} />
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
            {/* An unused slot: kept empty so the grid stays aligned. */}
            <Box width={19.6} mb={0} />
          </Stack.Item>
          <Stack.Item>
            {/*
            <NoticeBox info width={19.6} mb={0}>
            </NoticeBox>
            */}
            {/* An unused slot: kept empty so the grid stays aligned. */}
            <Box width={19.6} mb={0} />
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
          {/* An unused slot: kept empty so the grid stays aligned. */}
          <Box width={19.6} mb={0} />
        </Stack.Item>
        <Stack.Item>
          {/* An unused slot: kept empty so the grid stays aligned. */}
          <Box width={19.6} mb={0} />
        </Stack.Item>
      </Stack>
    </Stack>
  );
};
