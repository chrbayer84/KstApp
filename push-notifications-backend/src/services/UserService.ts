import UserSettingsService from './UserSettingsService';
import { UserSettings } from '../models/UserSettings';

/**
 * Service for managing user settings
 */
class UserService {
  /**
   * Get user settings by username
   */
  static async getSettings(username: string): Promise<UserSettings | undefined> {
    return await UserSettingsService.getSettings(username);
  }
  
  /**
   * Save or update user settings
   */
  static async saveSettings(settings: UserSettings): Promise<void> {
    await UserSettingsService.saveSettings(settings);
  }
  
  /**
   * Delete user settings
   */
  static async deleteUsername(username: string): Promise<boolean> {
    return await UserSettingsService.deleteSettings(username);
  }
  
  /**
   * Get all usernames
   */
  static getAllUsernames(): string[] {
    return UserSettingsService.getAllUsernames();
  }
}

export default UserService;
