import UserSettingsService from '../services/UserSettingsService';
import { UserSettings } from '../models/UserSettings';

describe('UserSettingsService', () => {
  const testUsername = 'TESTUSER';
  
  beforeEach(() => {
    // Clear any existing test data
    // Note: In a real test, we'd mock the storage or use a test database
  });
  
  afterEach(() => {
    // Clean up after each test
    // Note: In a real test, we'd clean up test data
  });
  
  it('should save and retrieve user settings', async () => {
    const settings: UserSettings = {
      username: testUsername,
      password: 'testpass',
      gridSquare: 'FN20rl',
      notificationsEnabled: true,
      notificationFilter: 'myCallsign',
      deviceToken: 'devicetoken123',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    // Save settings
    await UserSettingsService.saveSettings(settings);
    
    // Retrieve settings
    const retrieved = await UserSettingsService.getSettings(testUsername);
    
    expect(retrieved).toBeDefined();
    expect(retrieved?.username).toBe(testUsername);
    expect(retrieved?.password).toBe('testpass');
    expect(retrieved?.gridSquare).toBe('FN20rl');
    expect(retrieved?.notificationsEnabled).toBe(true);
    expect(retrieved?.notificationFilter).toBe('myCallsign');
    expect(retrieved?.deviceToken).toBe('devicetoken123');
  });
  
  it('should return undefined for non-existent user', async () => {
    const result = await UserSettingsService.getSettings('NONEXISTENT');
    expect(result).toBeUndefined();
  });
  
  it('should update existing settings', async () => {
    // Create initial settings
    const initialSettings: UserSettings = {
      username: testUsername,
      password: 'oldpass',
      notificationsEnabled: false,
      notificationFilter: 'all',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    await UserSettingsService.saveSettings(initialSettings);
    
    // Update settings
    const updatedSettings: UserSettings = {
      username: testUsername,
      password: 'newpass',
      notificationsEnabled: true,
      notificationFilter: 'myCallsign',
      deviceToken: 'newdevice token',
      createdAt: new Date(), // This should be preserved
      updatedAt: new Date()
    };
    
    await UserSettingsService.saveSettings(updatedSettings);
    
    // Retrieve and verify
    const retrieved = await UserSettingsService.getSettings(testUsername);
    expect(retrieved).toBeDefined();
    expect(retrieved?.password).toBe('newpass');
    expect(retrieved?.notificationsEnabled).toBe(true);
    expect(retrieved?.notificationFilter).toBe('myCallsign');
    expect(retrieved?.deviceToken).toBe('newdevice token');
    // createdAt should be preserved
    expect(retrieved?.createdAt).toEqual(initialSettings.createdAt);
  });
  
  it('should delete user settings', async () => {
    // Create settings
    const settings: UserSettings = {
      username: testUsername,
      password: 'testpass',
      notificationsEnabled: true,
      notificationFilter: 'all',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    await UserSettingsService.saveSettings(settings);
    
    // Verify it exists
    let retrieved = await UserSettingsService.getSettings(testUsername);
    expect(retrieved).toBeDefined();
    
    // Delete it
    const deleted = await UserSettingsService.deleteSettings(testUsername);
    expect(deleted).toBe(true);
    
    // Verify it's gone
    retrieved = await UserSettingsService.getSettings(testUsername);
    expect(retrieved).toBeUndefined();
  });
  
  it('should return false when deleting non-existent user', async () => {
    const deleted = await UserSettingsService.deleteSettings('NONEXISTENT');
    expect(deleted).toBe(false);
  });
});
