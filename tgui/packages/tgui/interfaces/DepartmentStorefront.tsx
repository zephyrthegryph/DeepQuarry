import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Box,
  Button,
  Flex,
  Input,
  LabeledList,
  NumberInput,
  Section,
  Stack,
} from 'tgui-core/components';

type StockItem = {
  ref: string;
  name: string;
  desc: string;
  suggested: number;
  price: number;
  quantity: number;
};

type Data = {
  department: string;
  balance: number;
  markup: number;
  authorized: boolean;
  stock: StockItem[];
};

export const DepartmentStorefront = (props) => {
  const { act, data } = useBackend<Data>();
  const { department, balance, markup, authorized, stock } = data;

  return (
    <Window width={620} height={560} title={`${department} Storefront`}>
      <Window.Content scrollable>
        <Section title="Store account">
          <LabeledList>
            <LabeledList.Item label="Revenue destination">
              {department} departmental budget
            </LabeledList.Item>
            {authorized && (
              <LabeledList.Item label="Operating balance">
                {balance} Thalers
              </LabeledList.Item>
            )}
            <LabeledList.Item label="Default markup">
              {authorized ? (
                <NumberInput
                  value={markup}
                  minValue={-90}
                  maxValue={500}
                  step={5}
                  unit="%"
                  onChange={(value) => act('set_markup', { markup: value })}
                />
              ) : (
                `${markup}%`
              )}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section title="Available goods">
          {!stock.length && (
            <Box color="label" textAlign="center" py={4}>
              No goods are currently stocked.
            </Box>
          )}
          <Stack vertical>
            {stock.map((item) => (
              <Stack.Item key={item.ref}>
                <Section
                  title={`${item.name} ×${item.quantity}`}
                  buttons={
                    <Button
                      icon="shopping-cart"
                      color="good"
                      onClick={() => act('buy', { ref: item.ref })}
                    >
                      Buy for {item.price} Th
                    </Button>
                  }
                >
                  <Box color="label" mb={1}>
                    {item.desc}
                  </Box>
                  <Flex align="center">
                    <Flex.Item grow>
                      Suggested market price: {item.suggested} Th
                    </Flex.Item>
                    {authorized && (
                      <Flex.Item>
                        <Input
                          width="90px"
                          value={String(item.price)}
                          onChange={(value) =>
                            act('set_price', { ref: item.ref, price: value })
                          }
                        />
                        <Button
                          ml={1}
                          icon="box-open"
                          onClick={() => act('withdraw', { ref: item.ref })}
                        >
                          Withdraw
                        </Button>
                      </Flex.Item>
                    )}
                  </Flex>
                </Section>
              </Stack.Item>
            ))}
          </Stack>
        </Section>
      </Window.Content>
    </Window>
  );
};
