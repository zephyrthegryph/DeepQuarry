import { Provider } from 'jotai';
import { store } from './events/store';
import { GenericWarmup } from './GenericWarmup';
import { RoutedComponent } from './routes';

export function App() {
  return (
    <Provider store={store}>
      <GenericWarmup />
      <RoutedComponent />
    </Provider>
  );
}
