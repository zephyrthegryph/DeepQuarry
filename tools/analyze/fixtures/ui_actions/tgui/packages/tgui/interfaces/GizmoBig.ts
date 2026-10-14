export const send = (act) => {
  act('spin', { rate: 3 });
  act('spin', { rate: 3, mode: 'x' });
  act('checks', {});
};
