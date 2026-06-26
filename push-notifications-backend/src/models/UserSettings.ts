export interface UserSettings {
  username: string;           // ON4KST username
  password: string;           // ON4KST password

  gridSquare?: string;        // Optional Maidenhead grid square

  notificationsEnabled: boolean;
  notificationFilter: 'all' | 'myCallsign';

  // Push notification tokens
  deviceToken?: string;       // For APNs (iOS device token)
  pushoverUserKey?: string;   // For Pushover

  // Notification service preference
  notificationService?: 'apns' | 'pushover';

  // Metadata
  createdAt: Date;
  updatedAt: Date;
}
