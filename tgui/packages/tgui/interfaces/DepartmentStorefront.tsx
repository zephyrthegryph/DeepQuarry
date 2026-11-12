import { useBackend } from 'tgui/backend';
import { Window } from 'tgui/layouts';
import {
  Button,
  Flex,
  Input,
  LabeledList,
  NumberInput,
  Section,
  Stack,
} from 'tgui-core/components';
import type {
  DepartmentStorefrontActions,
  DepartmentStorefrontData,
} from './generated/DepartmentStorefront';
import { Label } from 'tgui/components/Label';

export const DepartmentStorefront = (props) => {
  const { act, data } = useBackend<
    DepartmentStorefrontData,
    DepartmentStorefrontActions
  >();
  const { department, balance, markup, authorized, stock = [] } = data;

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
            <Label textAlign="center" py={4}>
              No goods are currently stocked.
            </Label>
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
                  <Label mb={1}>{item.desc}</Label>
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
