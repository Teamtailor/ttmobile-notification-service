import { requireNativeViewManager } from 'expo-modules-core';
import * as React from 'react';

import { TtmobileCommunicationNotificationsViewProps } from './TtmobileCommunicationNotifications.types';

const NativeView: React.ComponentType<TtmobileCommunicationNotificationsViewProps> =
  requireNativeViewManager('TtmobileCommunicationNotifications');

export default function TtmobileCommunicationNotificationsView(props: TtmobileCommunicationNotificationsViewProps) {
  return <NativeView {...props} />;
}
