export const Thing = (props) => {
  const { act } = useBackend();
  return (
    <>
      <Button onClick={() => act('go', { speed: 5 })} />
      <Button onClick={() => act("pick", {mode: 'a', 'ref': x.ref, flag})} />
      {act('raw', { amount: 1, name: `n`, kind, when: a ? b : c, extra: { nested: 1 } })}
      {act('sub', {level: true, items: [1, 2]})}
      {act('bolt-toggle', { targetState: true })}
      {act(dynamicName, { a: 1 })}
      {act('pick', { ...params })}
      {act('modal_close', params)}
      {act('bogus')}
      {act('go', { speed: 1, bogus: 2 })}
      {act('go', { user: 'x' })}
      {act('go', { 'bad key': 1 })}
      {act('bad name!')}
      {act('breaker', { channel: 2 })}
      {act('unknownThing', { whatever: 1 })}
      {act('multi', { amount: 1, items: 2 })}
      {act('atom_thing', { nothing: 1 })}
      {act(`go`, { speed: 1 })}
      {act(`go${x}`, { speed: 1 })}
      {act('esc\'aped', { a: 1 })}
      {act('go', { speed: 1, /* block act('commented') */ force: 2 })}
      {act('go', {
        speed: 1, // act('inline_comment') and a brace }
        force: `a${b}`,
      })}
      {act('go', { speed: 1, [computed]: 2 })}
      {act('go', { get x() { return 1; } })}
      {act('go', { speed() {}, force = 1 })}
      {act('go', { method() {}, shorthand })}
      {act('go',)}
      {act('go', {})}
      {act('go', ...args)}
      {act('go',
        { speed: 1,
          'force': 2 })}
      {act('go', { "speed": "}", force: '{' })}
      {act('go', {  speed:1 })}
      {act('日本', { 'é': 1 })}
      {act(`go
`, { speed: 1 })}
      {act('go' , { speed: 1 })}
      {myact('go', { nope: 1 })}
      {$act('go', { nope: 1 })}
      {this.act('go', { speed: 1 })}
    </>
  );
};
act('unterminated
