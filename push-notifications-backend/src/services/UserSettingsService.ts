import { UserSettings } from '../models/UserSettings';

// In-memory storage for now - can be replaced with database later
class UserSettingsService {
  private settings: Map<string, UserSettings> = new Map();

  /**
   * Save or update user settings
   */
  async saveSettings(settings: UserSettings): Promise<void> {
    settings.updatedAt = new Date();
    const existing = await this.getSettings(settings.username);
    if (!existing) {
      // New record - set createdAt if not already set
      if (!settings.createdAt) {
        settings.createdAt = new Date();
      }
    } else {
      // Existing record - preserve the original createdAt
      if (existing.createdAt) {
        settings.createdAt = existing.createdAt;
      }
      // If no existing createdAt (shouldn't happen but just in case), set it now
      else if (!settings.createdAt) {
        settings.createdAt = new Date();
      }
    }
    this.settings.set(settings.username, settings);
  }

  /**
   * Get user settings by username
   */
  async getSettings(username: string): Promise<UserSettings | undefined> {
    return this.settings.get(username);
  }

  /**
   * Delete user settings
   */
  async deleteSettings(username: string): Promise<boolean> {
    return this.settings.delete(username);
  }

  /**
   * Get all usernames
   */
  getAllUsernames(): string[] {
    return Array.from(this.settings.keys());
  }
}

export default new UserSettingsService();