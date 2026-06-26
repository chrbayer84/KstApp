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
});
