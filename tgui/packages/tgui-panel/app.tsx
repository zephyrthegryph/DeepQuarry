import { Provider } from 'jotai';
import { Column } from './column/Column';
import { store } from './events/store';

/** The right-hand column's page: one window manager for the chat, the stat panel and docked interfaces. */
export function App() {
  return (
    <Provider store={store}>
      <Column />
    </Provider>
  );
}
