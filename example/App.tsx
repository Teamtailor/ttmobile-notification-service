import { StyleSheet, Text, View } from 'react-native';

import * as TtmobileCommunicationNotifications from 'ttmobile-communication-notifications';

export default function App() {
  return (
    <View style={styles.container}>
      <Text>{TtmobileCommunicationNotifications.hello()}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
