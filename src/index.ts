import { NativeModulesProxy, EventEmitter, Subscription } from 'expo-modules-core';

// Import the native module. On web, it will be resolved to TtmobileCommunicationNotifications.web.ts
// and on native platforms to TtmobileCommunicationNotifications.ts
import TtmobileCommunicationNotificationsModule from './TtmobileCommunicationNotificationsModule';
import TtmobileCommunicationNotificationsView from './TtmobileCommunicationNotificationsView';
import { ChangeEventPayload, TtmobileCommunicationNotificationsViewProps } from './TtmobileCommunicationNotifications.types';

// Get the native constant value.
export const PI = TtmobileCommunicationNotificationsModule.PI;

export function hello(): string {
  return TtmobileCommunicationNotificationsModule.hello();
}

export async function setValueAsync(value: string) {
  return await TtmobileCommunicationNotificationsModule.setValueAsync(value);
}

const emitter = new EventEmitter(TtmobileCommunicationNotificationsModule ?? NativeModulesProxy.TtmobileCommunicationNotifications);

export function addChangeListener(listener: (event: ChangeEventPayload) => void): Subscription {
  return emitter.addListener<ChangeEventPayload>('onChange', listener);
}

export { TtmobileCommunicationNotificationsView, TtmobileCommunicationNotificationsViewProps, ChangeEventPayload };
