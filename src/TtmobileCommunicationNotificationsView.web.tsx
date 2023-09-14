import * as React from 'react';

import { TtmobileCommunicationNotificationsViewProps } from './TtmobileCommunicationNotifications.types';

export default function TtmobileCommunicationNotificationsView(props: TtmobileCommunicationNotificationsViewProps) {
  return (
    <div>
      <span>{props.name}</span>
    </div>
  );
}
