import NotificationService from '../services/NotificationService';
import UserSettingsService from '../services/UserSettingsService';
import { UserSettings } from '../models/UserSettings';

describe('NotificationService', () => {
  const testUsername = 'TESTNOTIFY';
  
  beforeEach(async () => {
    // Clear any existing test data
    await UserSettingsService.deleteSettings(testUsername);
    // Stop any existing connections
    await NotificationService.stopUserNotifications(testUsername);
  });
  
  afterEach(async () => {
    // Clean up after each test
    await NotificationService.stopUserNotifications(testUsername);
    await UserSettingsService.deleteSettings(testUsername);
  });
  
  it('should start and stop user notifications', async () => {
    const settings: UserSettings = {
      username: testUsername,
      password: 'testpass',
      notificationsEnabled: true,
      notificationFilter: 'all',
      deviceToken: 'devicetoken123',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    // Start notifications
    await NotificationService.startUserNotifications(settings);
    
    // Check that connection is active
    const activeConnections = NotificationService.getActiveConnections();
    expect(activeConnections).toContain(testUsername);
    
    // Stop notifications
    await NotificationService.stopUserNotifications(testUsername);
    
    // Check that connection is no longer active
    const activeConnectionsAfterStop = NotificationService.getActiveConnections();
    expect(activeConnectionsAfterStop).not.toContain(testUsername);
  });
  
  it('should not start notifications when disabled', async () => {
    const settings: UserSettings = {
      username: testUsername,
      password: 'testpass',
      notificationsEnabled: false, // Disabled
      notificationFilter: 'all',
      deviceToken: 'devicetoken123',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    // Start notifications (should not actually connect)
    await NotificationService.startUserNotifications(settings);
    
    // Check that no connection was started
    const activeConnections = NotificationService.getActiveConnections();
    expect(activeConnections).not.toContain(testUsername);
  });
  
  it('should handle settings updates', async () => {
    // Initial settings with notifications enabled
    const initialSettings: UserSettings = {
      username: testUsername,
      password: 'initialpass',
      notificationsEnabled: true,
      notificationFilter: 'all',
      deviceToken: 'initialtoken',
      createdAt: new Date(),
      updatedAt: new Date()
    };

    await NotificationService.startUserNotifications(initialSettings);
    let activeConnections = NotificationService.getActiveConnections();
    expect(activeConnections).toContain(testUsername);

    // Update settings to disable notifications
    const updatedSettings: UserSettings = {
      username: testUsername,
      password: 'updatedpass',
      notificationsEnabled: false, // Now disabled
      notificationFilter: 'all',
      deviceToken: 'updatedtoken',
      createdAt: new Date(),
      updatedAt: new Date()
    };

    await NotificationService.startUserNotifications(updatedSettings);
    activeConnections = NotificationService.getActiveConnections();
    expect(activeConnections).not.toContain(testUsername);
  });

  describe('myCallsign filter', () => {
    const callsignUser = 'WA4YA';

    beforeEach(async () => {
      await UserSettingsService.deleteSettings(callsignUser);
      await NotificationService.stopUserNotifications(callsignUser);
    });

    afterEach(async () => {
      await NotificationService.stopUserNotifications(callsignUser);
      await UserSettingsService.deleteSettings(callsignUser);
    });

    it('should match callsign in uppercase', async () => {
      const settings: UserSettings = {
        username: callsignUser,
        password: 'testpass',
        notificationsEnabled: true,
        notificationFilter: 'myCallsign',
        deviceToken: 'testtoken',
        createdAt: new Date(),
        updatedAt: new Date()
      };

      // Save settings first so handleIncomingMessage can retrieve them
      await UserSettingsService.saveSettings(settings);

      // Simulate message containing callsign (uppercase)
      const testMessage = {
        time: '1200Z',
        sender: 'K8NWN',
        message: 'Hello WA4YA, are you there?'
      };

      // Access private method via type assertion for testing
      const result = await (NotificationService as any).handleIncomingMessage(callsignUser, testMessage);

      // Should send notification (callsign matched) - returns undefined on success
      expect(result).toBeUndefined();
    });

    it('should match callsign in lowercase (case-insensitive)', async () => {
      const settings: UserSettings = {
        username: callsignUser,
        password: 'testpass',
        notificationsEnabled: true,
        notificationFilter: 'myCallsign',
        deviceToken: 'testtoken',
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await UserSettingsService.saveSettings(settings);

      // Simulate message containing callsign (lowercase)
      const testMessage = {
        time: '1200Z',
        sender: 'K8NWN',
        message: 'Hello wa4ya, are you there?'
      };

      const result = await (NotificationService as any).handleIncomingMessage(callsignUser, testMessage);

      // Should send notification (callsign matched, case-insensitive)
      expect(result).toBeUndefined();
    });

    it('should match callsign in mixed case', async () => {
      const settings: UserSettings = {
        username: callsignUser,
        password: 'testpass',
        notificationsEnabled: true,
        notificationFilter: 'myCallsign',
        deviceToken: 'testtoken',
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await UserSettingsService.saveSettings(settings);

      // Simulate message containing callsign (mixed case)
      const testMessage = {
        time: '1200Z',
        sender: 'K8NWN',
        message: 'Looking for Wa4Ya on 144MHz'
      };

      const result = await (NotificationService as any).handleIncomingMessage(callsignUser, testMessage);

      // Should send notification (callsign matched, case-insensitive)
      expect(result).toBeUndefined();
    });

    it('should NOT match when callsign is absent', async () => {
      const settings: UserSettings = {
        username: callsignUser,
        password: 'testpass',
        notificationsEnabled: true,
        notificationFilter: 'myCallsign',
        deviceToken: 'testtoken',
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await UserSettingsService.saveSettings(settings);

      // Simulate message NOT containing callsign
      const testMessage = {
        time: '1200Z',
        sender: 'W8ZN',
        message: 'Terry 50 - 24G'
      };

      const result = await (NotificationService as any).handleIncomingMessage(callsignUser, testMessage);

      // Should return early (no notification sent)
      expect(result).toEqual({ notified: false, reason: 'filter_rejected' });
    });

    it('should NOT match other callsigns that don\'t contain the filter', async () => {
      const settings: UserSettings = {
        username: callsignUser,
        password: 'testpass',
        notificationsEnabled: true,
        notificationFilter: 'myCallsign',
        deviceToken: 'testtoken',
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await UserSettingsService.saveSettings(settings);

      // Simulate messages from other users without mentioning WA4YA
      const messages = [
        { time: '1200Z', sender: 'K8NWN', message: 'Michael' },
        { time: '1201Z', sender: 'KC2KAE', message: 'Frank SSB' },
        { time: '1202Z', sender: 'W8ZN', message: 'Terry 50 - 24G' }
      ];

      for (const msg of messages) {
        const result = await (NotificationService as any).handleIncomingMessage(callsignUser, msg);
        expect(result).toEqual({ notified: false, reason: 'filter_rejected' });
      }
    });
  });
});
