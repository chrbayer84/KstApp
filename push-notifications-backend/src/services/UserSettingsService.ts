import { UserSettings } from '../models/UserSettings';
import {
  decryptOptional,
  decryptString,
  encryptOptional,
  encryptString
} from '../utils/crypto';

/**
 * In-memory representation of user settings. Sensitive fields are ciphertext.
 */
interface EncryptedUserSettings {
  username: string;
  password: string;
  gridSquare?: string;
  on4kstRoom?: number;
  notificationsEnabled: boolean;
  notificationFilter: 'all' | 'myCallsign';
  deviceToken?: string;
  pushoverUserKey?: string;
  notificationService?: 'apns' | 'pushover';
  createdAt: Date;
  updatedAt: Date;
}

export type SafeUserSettings = Omit<
  UserSettings,
  'password' | 'deviceToken' | 'pushoverUserKey'
>;

// In-memory storage for now - can be replaced with a database later.
// Sensitive values (ON4KST password, Pushover user key, APNs device token)
// are encrypted with AES-256-GCM before they are placed in the map.
class UserSettingsService {
  private settings: Map<string, EncryptedUserSettings> = new Map();

  /**
   * Save or update user settings
   */
  async saveSettings(settings: UserSettings): Promise<void> {
    settings.updatedAt = new Date();
    const existing = this.settings.get(settings.username);
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

    const encrypted: EncryptedUserSettings = {
      username: settings.username,
      password: encryptString(settings.password),
      gridSquare: settings.gridSquare,
      on4kstRoom: settings.on4kstRoom,
      notificationsEnabled: settings.notificationsEnabled,
      notificationFilter: settings.notificationFilter,
      deviceToken: encryptOptional(settings.deviceToken),
      pushoverUserKey: encryptOptional(settings.pushoverUserKey),
      notificationService: settings.notificationService,
      createdAt: settings.createdAt,
      updatedAt: settings.updatedAt
    };

    this.settings.set(settings.username, encrypted);
  }

  /**
   * Get user settings by username, decrypting sensitive fields.
   */
  async getSettings(username: string): Promise<UserSettings | undefined> {
    const record = this.settings.get(username);
    if (!record) {
      return undefined;
    }

    return {
      username: record.username,
      password: decryptString(record.password),
      gridSquare: record.gridSquare,
      on4kstRoom: record.on4kstRoom,
      notificationsEnabled: record.notificationsEnabled,
      notificationFilter: record.notificationFilter,
      deviceToken: decryptOptional(record.deviceToken),
      pushoverUserKey: decryptOptional(record.pushoverUserKey),
      notificationService: record.notificationService,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt
    };
  }

  /**
   * Get settings without sensitive fields. Does not decrypt anything.
   */
  async getSafeSettings(username: string): Promise<SafeUserSettings | undefined> {
    const record = this.settings.get(username);
    if (!record) {
      return undefined;
    }

    return {
      username: record.username,
      gridSquare: record.gridSquare,
      on4kstRoom: record.on4kstRoom,
      notificationsEnabled: record.notificationsEnabled,
      notificationFilter: record.notificationFilter,
      notificationService: record.notificationService,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt
    };
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
