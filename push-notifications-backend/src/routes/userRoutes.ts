import { Router, Request, Response, NextFunction } from 'express';
import { createLogger } from "../utils/logger";
const log = createLogger("kst:routes");
import UserSettingsService from '../services/UserSettingsService';
import NotificationService from '../services/NotificationService';
import { UserSettings } from '../models/UserSettings';

const router = Router();

/**
 * Helper to get string value from possibly array-valued query/body/param
 */
const getStringParam = (value: string | string[] | undefined): string | undefined => {
  if (value === undefined) return undefined;
  if (Array.isArray(value)) return value[0];
  return value;
};

/**
 * Helper to get boolean value from possibly array-valued input
 */
const getBooleanParam = (value: any): boolean => {
  if (value === true || value === 'true') return true;
  if (Array.isArray(value)) {
    return value.some(v => v === true || v === 'true');
  }
  return false;
};

/**
 * Middleware to validate request body contains required fields
 */
const validateUserSettings = (req: Request, res: Response, next: NextFunction) => {
  const { on4kstUsername, on4kstPassword, notificationsEnabled, notificationFilter } = req.body;
  
  // Extract values, handling possible arrays
  const username = getStringParam(on4kstUsername);
  const password = getStringParam(on4kstPassword);
  const enabled = getBooleanParam(notificationsEnabled);
  const filter = getStringParam(notificationFilter);
  
  if (!username || !password) {
    return res.status(400).json({ 
      error: 'Missing required fields: on4kstUsername and on4kstPassword are required' 
    });
  }
  
  if (typeof enabled !== 'boolean') {
    return res.status(400).json({ 
      error: 'notificationsEnabled must be a boolean' 
    });
  }
  
  if (filter && !['all', 'myCallsign'].includes(filter)) {
    return res.status(400).json({ 
      error: 'notificationFilter must be either "all" or "myCallsign"' 
    });
  }
  
  next();
};

/**
 * Save or update user settings
 * PUT /api/v1/user/:username
 */
router.put('/:username', validateUserSettings, async (req: Request, res: Response) => {
  try {
    const usernameParam = getStringParam(req.params.username);
    if (!usernameParam) {
      return res.status(400).json({ error: 'Username parameter is required' });
    }
    
    const {
      on4kstUsername,
      on4kstPassword,
      gridSquare,
      notificationsEnabled,
      notificationFilter,
      deviceToken,
      pushoverUserKey,
      notificationService
    } = req.body;

    // Extract values, handling possible arrays
    const username = getStringParam(on4kstUsername);
    const password = getStringParam(on4kstPassword);
    const grid = getStringParam(gridSquare);
    const enabled = getBooleanParam(notificationsEnabled);
    const filter = getStringParam(notificationFilter);
    const token = getStringParam(deviceToken);
    const pushKey = getStringParam(pushoverUserKey);
    const service = getStringParam(notificationService);
    
    // Validate required fields
    if (!username || !password) {
      return res.status(400).json({
        error: 'Missing required fields: on4kstUsername and on4kstPassword are required'
      });
    }

    if (typeof enabled !== 'boolean') {
      return res.status(400).json({
        error: 'notificationsEnabled must be a boolean'
      });
    }

    if (filter && !['all', 'myCallsign'].includes(filter)) {
      return res.status(400).json({
        error: 'notificationFilter must be either "all" or "myCallsign"'
      });
    }

    if (service && !['apns', 'pushover'].includes(service)) {
      return res.status(400).json({
        error: 'notificationService must be either "apns" or "pushover"'
      });
    }

    // Verify that the username in params matches the one in body (for security)
    if (username?.toUpperCase() !== usernameParam.toUpperCase()) {
      return res.status(400).json({
        error: 'Username in URL must match username in request body'
      });
    }
    
    // Create settings object
    const settings: UserSettings = {
      username: username.toUpperCase(), // ON4KST uses uppercase
      password: password!,
      gridSquare: grid || undefined,
      notificationsEnabled: !!enabled,
      notificationFilter: (filter === 'all' || filter === 'myCallsign') ? filter : 'all',
      deviceToken: token || undefined,
      pushoverUserKey: pushKey || undefined,
      notificationService: service ? (service as 'apns' | 'pushover') : undefined,
      createdAt: new Date(), // Will be corrected by service if exists
      updatedAt: new Date()
    };
    
    // Save settings
    await UserSettingsService.saveSettings(settings);

    // Handle notifications based on enabled status
    if (enabled) {
      // Start notifications for this user
      await NotificationService.startUserNotifications(settings);
    } else {
      // Stop notifications for this user
      await NotificationService.stopUserNotifications(usernameParam);
    }

    res.json({
      message: `${enabled ? 'Notifications enabled' : 'Notifications disabled'} for user ${usernameParam}`,
      username: usernameParam
    });
  } catch (error) {
    log.error('Error saving user settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/*
 * Get user settings
 * GET /api/v1/user/:username
 */
router.get('/:username', async (req: Request, res: Response) => {
  try {
    const usernameParam = getStringParam(req.params.username);
    if (!usernameParam) {
      return res.status(400).json({ error: 'Username parameter is required' });
    }
    
    const settings = await UserSettingsService.getSettings(usernameParam);
    
    if (!settings) {
      return res.status(404).json({ error: `User settings not found for ${usernameParam}` });
    }
    
    // Return settings without sensitive information
    const { password, ...safeSettings } = settings;
    // Return with username from URL parameter to ensure consistency
    // Exclude username from spread to avoid duplication
    const { username: _, ...safeSettingsWithoutUsername } = safeSettings;
    res.json({
      username: usernameParam.toUpperCase(),
      ...safeSettingsWithoutUsername
    });
  } catch (error) {
    log.error('Error getting user settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/*
 * Delete user settings
 * DELETE /api/v1/user/:username
 */
router.delete('/:username', async (req: Request, res: Response) => {
  try {
    const usernameParam = getStringParam(req.params.username);
    if (!usernameParam) {
      return res.status(400).json({ error: 'Username parameter is required' });
    }
    
    // Stop notifications first
    await NotificationService.stopUserNotifications(usernameParam);
    
    // Delete settings
    const deleted = await UserSettingsService.deleteSettings(usernameParam);
    
    if (!deleted) {
      return res.status(404).json({ error: `User settings not found for ${usernameParam}` });
    }
    
    res.json({ message: `User settings deleted for user ${usernameParam}` });
  } catch (error) {
    log.error('Error deleting user settings:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/*
 * Get all users
 * GET /api/v1/users
 */
router.get('/', async (req: Request, res: Response) => {
  try {
    const usernames = UserSettingsService.getAllUsernames();
    const usersPromises = usernames.map(async (username) => {
      const settings = await UserSettingsService.getSettings(username);
      if (settings) {
        const { password, ...safeSettings } = settings;
        // Remove username from safeSettings to avoid duplication when we add it back
        const { username: _, ...userSettingsWithoutUsername } = safeSettings;
        return {
          username: username,
          ...(userSettingsWithoutUsername as Omit<UserSettings, 'password' | 'username'>)
        };
      }
      return null;
    });

    const users = (await Promise.all(usersPromises)).filter((u): u is NonNullable<typeof u> => u !== null);
    res.json({ users, count: users.length });
  } catch (error) {
    log.error('Error getting users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/*
 * Get connection debug state for a user
 * GET /api/v1/user/:username/debug
 */
router.get('/:username/debug', async (req: Request, res: Response) => {
  try {
    const usernameParam = getStringParam(req.params.username);
    if (!usernameParam) {
      return res.status(400).json({ error: 'Username parameter is required' });
    }

    const username = usernameParam.toUpperCase();
    const connection = NotificationService.getActiveConnections().includes(username)
      ? (NotificationService as any).connections?.get(username)
      : null;

    if (!connection) {
      return res.json({
        username,
        connected: false,
        message: 'No active connection for this user. Check if notifications are enabled and the user was registered.'
      });
    }

    // The connection manager is internal, but we can expose its debug state if it has one
    const debugState = connection.getDebugState ? connection.getDebugState() : {
      username,
      connected: connection.isConnectedStatus?.(),
      note: 'getDebugState() method not available on connection manager'
    };

    res.json(debugState);
  } catch (error) {
    log.error('Error getting debug state:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/*
 * Send a test Pushover notification to a user
 * POST /api/v1/user/:username/test-pushover
 */
router.post('/:username/test-pushover', async (req: Request, res: Response) => {
  try {
    const usernameParam = getStringParam(req.params.username);
    if (!usernameParam) {
      return res.status(400).json({ error: 'Username parameter is required' });
    }

    const result = await NotificationService.testPushoverNotification(usernameParam);
    if (result.success) {
      res.json({ success: true, message: result.detail });
    } else {
      res.status(400).json({ success: false, error: result.detail });
    }
  } catch (error) {
    log.error('Error sending test Pushover notification:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/*
 * Simulate an incoming ON4KST message for testing filter/push pipeline
 * POST /api/v1/user/:username/simulate-message
 * Body: { sender: "ON1ABC", message: "Test message (ON4KST)" }
 */
router.post('/:username/simulate-message', async (req: Request, res: Response) => {
  try {
    const usernameParam = getStringParam(req.params.username);
    if (!usernameParam) {
      return res.status(400).json({ error: 'Username parameter is required' });
    }

    const { sender, message } = req.body;
    if (!sender || !message) {
      return res.status(400).json({ error: 'sender and message are required in request body' });
    }

    const result = await NotificationService.simulateMessage(usernameParam, sender, message);
    if (result.notified) {
      res.json({ success: true, message: result.detail });
    } else {
      res.status(400).json({ success: false, error: result.detail });
    }
  } catch (error) {
    log.error('Error simulating message:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
