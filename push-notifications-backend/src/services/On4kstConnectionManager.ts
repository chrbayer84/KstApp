import net from 'net';
import { UserSettings } from '../models/UserSettings';
import UserSettingsService from './UserSettingsService';
import { createLogger } from '../utils/logger';

const log = createLogger('kst:connection');

// Message types
interface ChatMessage {
  time: string;     // HHMM format (UTC)
  sender: string;   // Callsign
  message: string;  // Message text
}

interface CommandResponse {
  success: boolean;
  data?: string;
  error?: string;
}

// Command types that we send to the ON4KST server
enum Command {
  LOGIN = 'login',
  PASSWORD = 'password',
  SET_GRID = 'set_grid',
  SHOW_USERS = 'show_users',
  SHOW_MESSAGES = 'show_messages',
  USER = 'user',
  NONE = 'none'
}

/**
 * Manages a single connection to the ON4KST server for a specific user
 */
class On4kstConnectionManager {
  private username: string;
  private settings: UserSettings | undefined;
  private connection: net.Socket | null = null;
  private receiveBuffer: string = '';
  private commandQueue: Array<{ command: Command; message: string; resolve: (value: CommandResponse | PromiseLike<CommandResponse>) => void; reject: (reason?: any) => void }> = [];
  private currentCommand: Command = Command.NONE;
  private commandLineBuffer: string[] = [];
  private isConnected: boolean = false;
  private isLoggedIn: boolean = false;
  private isWaitingForLoginPrompt: boolean = false;
  private reconnectAttempts: number = 0;
  private baseReconnectDelay: number = 5000; // Start with 5 seconds
  private maxReconnectDelay: number = 30000; // Cap at 30 seconds
  private shouldReconnect: boolean = true; // Set to false on auth errors
  private reconnectTimer: NodeJS.Timeout | null = null;
  private livenessTimer: NodeJS.Timeout | null = null;
  private lastDataTimestamp: number = 0;
  private livenessCheckIntervalMs: number = 30000; // Check every 30 seconds
  private livenessTimeoutMs: number = 90000; // Declare dead after 90 seconds of no data
  private initialConnectResolve: ((value: void | PromiseLike<void>) => void) | null = null;

  // Message deduplication - prevent duplicate notifications
  private recentMessageIds: Set<string> = new Set();
  private maxRecentMessages = 100;

  // Callbacks
  private onMessageReceived: ((message: ChatMessage) => void) | null = null;
  private onConnectionStatusChange: ((isConnected: boolean) => void) | null = null;
  private onError: ((error: Error) => void) | null = null;

  constructor(username: string) {
    this.username = username.toUpperCase(); // ON4KST uses uppercase callsigns
  }

  // Diagnostic state tracking
  private lastMessages: string[] = [];
  private diagnosticStats = {
    linesReceived: 0,
    chatMessagesDetected: 0,
    commandCompletions: 0,
    unrecognizedLines: 0,
    lastActivityAt: ''
  };

  /**
   * Set the user settings for this connection
   */
  setSettings(settings: UserSettings): void {
    this.settings = settings;
  }

  /**
   * Set callback for when a message is received
   */
  setOnMessageReceived(callback: (message: ChatMessage) => void): void {
    this.onMessageReceived = callback;
  }

  /**
   * Set callback for when connection status changes
   */
  setOnConnectionStatusChange(callback: (isConnected: boolean) => void): void {
    this.onConnectionStatusChange = callback;
  }

  /**
   * Set callback for when an error occurs
   */
  setOnError(callback: (error: Error) => void): void {
    this.onError = callback;
  }

  /**
   * Connect to the ON4KST server
   */
  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      // Close any existing connection and clean timers
      this.cleanupSocketAndTimers();

      // Store resolver for use by reconnection logic
      // On first connect, this resolve is the user-facing promise.
      // On reconnects initiated by attemptReconnect(), this is a no-op stub
      // since the original promise was already resolved.
      this.initialConnectResolve = resolve;

      // Create new connection
      this.connection = new net.Socket();

      this.connection.on('connect', () => {
        log.info('TCP socket connected to ON4KST server');
        this.isConnected = true;
        this.isLoggedIn = false;
        this.isWaitingForLoginPrompt = true;
        this.currentCommand = Command.NONE;
        this.commandLineBuffer = [];
        this.receiveBuffer = '';
        this.lastDataTimestamp = Date.now();

        // Start liveness monitoring
        this.startLivenessMonitor();

        // Notify connection status change
        if (this.onConnectionStatusChange) {
          this.onConnectionStatusChange(true);
        }

        // Resolve the original connect() promise only on initial connect
        if (this.initialConnectResolve) {
          this.initialConnectResolve();
          this.initialConnectResolve = null;
        }
      });

      this.connection.on('data', (data: Buffer) => {
        this.lastDataTimestamp = Date.now(); // Reset liveness timer on any data
        this.processReceivedData(data.toString('utf8'));
      });

      this.connection.on('error', (error: Error) => {
        log.error(`Connection error: ${error.message}`);
        this.isConnected = false;
        this.isLoggedIn = false;
        this.handleError(error);

        // Trigger reconnection — never reject the original promise;
        // the error is just an event we react to.
        if (this.shouldReconnect) {
          this.attemptReconnect();
        }
      });

      this.connection.on('close', (hadError: boolean) => {
        log.info(`Connection closed${hadError ? ' with error' : ''}`);
        this.isConnected = false;
        this.isLoggedIn = false;

        // Stop liveness monitor
        this.stopLivenessMonitor();

        // Notify connection status change
        if (this.onConnectionStatusChange) {
          this.onConnectionStatusChange(false);
        }

        // Try to reconnect only if we should
        if (this.shouldReconnect) {
          this.attemptReconnect();
        } else {
          log.info('Reconnection skipped: auth error or manual disconnect');
        }
      });

      this.connection.connect({
        host: 'www.on4kst.info',
        port: 23000
      });
    });
  }

  /**
   * Disconnect from the ON4KST server — permanent, no reconnect
   */
  disconnect(): void {
    this.shouldReconnect = false; // Prevent auto-reconnect
    this.stopLivenessMonitor();
    this.clearReconnectTimer();
    this.cleanupSocketAndTimers();
    log.info(`Permanent disconnect for ${this.username}`);
  }

  /**
   * Clean up socket and all timers (used by both disconnect and before re-connect)
   */
  private cleanupSocketAndTimers(): void {
    if (this.connection) {
      this.connection.removeAllListeners();
      this.connection.destroy();
      this.connection = null;
    }

    this.isConnected = false;
    this.isLoggedIn = false;
    this.isWaitingForLoginPrompt = false;
    this.currentCommand = Command.NONE;
    this.commandQueue = [];
    this.commandLineBuffer = [];
    this.receiveBuffer = '';
  }

  /**
   * Send a message (chat message) to the ON4KST server
   */
  sendMessage(message: string): void {
    if (!this.connection || !this.isConnected) {
      throw new Error('Not connected to ON4KST server');
    }
    
    // For regular messages, we send them as-is with CRLF
    const data = message + '\r\n';
    this.connection.write(data);
  }

  /**
   * Write raw data to the socket (for login sequence only)
   */
  private writeToSocket(message: string): void {
    if (!this.connection || !this.isConnected) {
      log.error('Cannot write to socket: not connected');
      return;
    }
    log.debug(`Writing to socket: ${message}`);
    this.connection.write(message + '\r\n');
  }

  /**
   * Send a command to the ON4KST server
   */
  private sendCommand(command: Command, message: string): Promise<CommandResponse> {
    return new Promise((resolve, reject) => {
      // If we're already processing a command, queue this one
      if (this.currentCommand !== Command.NONE) {
        log.debug(`Queueing leftover command: ${this.currentCommand} - waiting for completion`);
        this.commandQueue.push({ command, message, resolve, reject });
        return;
      }

      this.executeCommand(command, message, resolve, reject);
    });
  }

  /**
   * Execute a command immediately (internal use only)
   */
  private executeCommand(command: Command, message: string, resolve: (value: CommandResponse | PromiseLike<CommandResponse>) => void, reject: (reason?: any) => void): void {
    // Set current command (except for NONE which is used for raw messages)
    if (command !== Command.NONE) {
      this.currentCommand = command;
      this.commandLineBuffer = [];
    }

    // Send the command
    if (!this.connection || !this.isConnected) {
      reject(new Error('Not connected to ON4KST server'));
      return;
    }

    const data = message + '\r\n';
    log.debug(`Sending command [${command}]: ${message}`);
    this.connection.write(data, (err) => {
      if (err) {
        log.error(`Error sending command: ${err.message}`);
        reject(err);
      }
      // Resolution will happen when we receive the command completion signal
    });
  }

  /**
   * Process the command queue, sending any pending commands
   */
  private processCommandQueue(): void {
    if (this.commandQueue.length === 0) {
      return;
    }
    if (this.currentCommand !== Command.NONE) {
      log.debug(`Cannot process command queue, current command is: ${this.currentCommand}`);
      return;
    }

    const next = this.commandQueue.shift()!;
    log.debug(`Processing queued command: ${next.command}`);
    this.executeCommand(next.command, next.message, next.resolve, next.reject);

    // Keep processing if there are more
    if (this.commandQueue.length > 0) {
      this.processCommandQueue();
    }
  }

  /**
   * Process incoming data from the socket
   */
  private processReceivedData(data: string): void {
    // Log raw received data for debugging (useful to see what ON4KST sends)
    log.debug(`RAW RX [${data.length} bytes]: ${JSON.stringify(data)}`);

    this.receiveBuffer += data;
    const lines = this.splitLines();

    for (const line of lines) {
      this.processLine(line.trim());
    }

    // Check if we're still waiting for login prompt and have more data
    if (this.isWaitingForLoginPrompt && this.receiveBuffer.length > 0) {
      // Keep waiting - the prompt might come in chunks
      log.debug(`Still waiting for login prompt, buffer has ${this.receiveBuffer.length} bytes: ${JSON.stringify(this.receiveBuffer)}`);
    }
  }

  /**
   * Split the receive buffer into lines
   */
  private splitLines(): string[] {
    const lines: string[] = [];
    
    // Handle both \n and \r\n line endings
    const parts = this.receiveBuffer.split(/\r?\n/);
    
    // If we have more than one part, we have complete lines
    if (parts.length > 1) {
      // All but the last part are complete lines
      for (let i = 0; i < parts.length - 1; i++) {
        const line = parts[i].trim();
        if (line) {
          lines.push(line);
        }
      }
      
      // Keep the last part (incomplete line) in the buffer
      this.receiveBuffer = parts[parts.length - 1] || '';
    }
    
    return lines;
  }

  /**
   * Process a single line of input from the server
   */
  private processLine(line: string): void {
    if (!line) {
      return;
    }

    this.diagnosticStats.linesReceived++;
    this.diagnosticStats.lastActivityAt = new Date().toISOString();
    this.addToRecentMessage(line);
    log.debug(`[LINE] "${line.substring(0,100)}" | waitingLogin=${this.isWaitingForLoginPrompt} currentCmd=${this.currentCommand}`);

    // Handle login prompts - use direct socket writes to avoid command queue issues
    if (line.startsWith('Login:')) {
      log.info('Received login prompt, sending username');
      this.isWaitingForLoginPrompt = false;
      if (this.settings) {
        this.writeToSocket(this.settings.username);
      } else {
        log.error('No settings available for login!');
      }
      return;
    }

    if (line.startsWith('Password:')) {
      log.info('Received password prompt, sending password');
      this.isWaitingForLoginPrompt = false;
      if (this.settings) {
        this.writeToSocket(this.settings.password);
      } else {
        log.error('No settings available for password!');
      }
      return;
    }

    if (line.startsWith('Your choice')) {
      const roomChoice = (this.settings?.on4kstRoom ?? 0) + 1; // stored 0-indexed → server 1-indexed
      log.info(`Received room selection prompt, selecting room ${roomChoice} (${this.getRoomName()})`);
      this.isWaitingForLoginPrompt = false;
      this.writeToSocket(roomChoice.toString());
      this.isLoggedIn = true;
      this.reconnectAttempts = 0;
      log.info('Login sequence complete');
      return;
    }

    // Handle error messages
    if (line.startsWith('Unknown user')) {
      this.shouldReconnect = false;
      this.handleError(new Error('Unknown user'));
      return;
    }

    if (line.startsWith('Wrong password!')) {
      this.shouldReconnect = false;
      this.handleError(new Error('Invalid password'));
      return;
    }

    // Check for command completion
    if (this.isWaitingForResponse(line)) {
      log.debug(`[CLASSIFY] treating as command completion: "${line.substring(0,100)}"`);
      this.diagnosticStats.commandCompletions++;
      this.handleCommandCompletion(line);
      return;
    }

    // If we're waiting for login prompt, ignore other lines
    if (this.isWaitingForLoginPrompt) {
      log.debug(`[CLASSIFY] ignoring line during login wait: "${line.substring(0,100)}"`);
      return;
    }

    // Check if this is a chat message
    if (this.isChatMessage(line)) {
      log.debug(`[CLASSIFY] detected as chat message: "${line.substring(0,100)}"`);
      this.diagnosticStats.chatMessagesDetected++;
      this.handleChatMessage(line);
      return;
    }

    // If we're expecting a command response, add to buffer
    if (this.currentCommand !== Command.NONE) {
      log.debug(`[CLASSIFY] buffering for command ${this.currentCommand}: "${line.substring(0,100)}"`);
      this.commandLineBuffer.push(line);
      return;
    }

    // Ignore common server messages (room menu, welcome, info)
    if (line.trim() === '' ||
        line.startsWith('Chat selection') ||
        line.includes('MHz') ||
        line.startsWith('Microwave') ||
        line.startsWith('EME/') ||
        line.startsWith('Low Band') ||
        line.startsWith('kHz (') ||
        line.startsWith('Warc (') ||
        line.startsWith('Welcome ') ||
        line.startsWith('Use the inline ON4KST') ||
        line.startsWith('More info type') ||
        line.match(/^\d+ MHz/) ||
        line.match(/^\d{3,4} MHz/) ||
        line.match(/IARU/) ||
        line.match(/\.{3,}\d+$/)) {
      log.debug(`[CLASSIFY] Ignoring expected server message: "${line.substring(0, 80)}..."`);
      return;
    }

    // Unrecognized line - log at debug level since most are harmless
    this.diagnosticStats.unrecognizedLines++;
    log.debug(`[CLASSIFY] Unrecognized line: "${line}"`);
  }

  /**
   * Check if we're waiting for a response to a command we sent.
   * For ROOM commands, the prompt may still show the old room name,
   * so we match against any room name.
   */
  private isWaitingForResponse(line: string): boolean {
    // Match common pattern: HHMMZ <OUR_USERNAME> ... chat>...
    const pattern = new RegExp(`^([0-9]{4})Z ${this.username} .* chat>.*$`);
    return pattern.test(line);
  }

  /**
   * Get the current room name based on settings
   */
  private getRoomName(): string {
    // Default to first room (50/70 MHz) if no settings
    const roomIndex = this.settings?.on4kstRoom !== undefined && this.settings.on4kstRoom !== null
      ? this.settings.on4kstRoom
      : 0; // Default to 0 (50/70 MHz)

    const rooms = [
      "50/70 MHz",
      "144/432 MHz",
      "Microwave",
      "EME/JT65",
      "Low Band (160-80m)",
      "50 MHz IARU Region 3",
      "50 MHz IARU Region 2",
      "144/432 MHz IARU R 2",
      "144/432 MHz IARU R 3",
      "kHz (2000-630m)",
      "Warc (30,17,12m)",
      "28 MHz",
      "40 MHz"
    ];

    // Ensure roomIndex is within bounds
    const safeIndex = Math.max(0, Math.min(roomIndex, rooms.length - 1));
    return rooms[safeIndex];
  }

  /**
   * Handle command completion
   */
  private handleCommandCompletion(line: string): void {
    // Extract the message part after "chat>"
    const match = line.match(/^([0-9]{4})Z [^>]+>chat>(.*)$/);
    const messageContent = match ? match[2] : '';

    let response: CommandResponse = { success: true, data: messageContent };

    log.debug(`Handling command completion for: ${this.currentCommand}`);

    // Process based on the command we were waiting for
    switch (this.currentCommand) {
      case Command.LOGIN:
        // Login completed successfully
        this.isConnected = true;
        this.reconnectAttempts = 0; // Reset reconnect counter on success
        if (messageContent.trim()) {
          this.addToChatMessageBuffer(messageContent);
        }
        break;

      case Command.SET_GRID:
        // Grid set completed
        if (messageContent.trim()) {
          this.addToChatMessageBuffer(messageContent);
        }
        break;

      case Command.SHOW_MESSAGES:
        // Message history received - we don't notify on history, just consume it
        log.info(`Processed ${this.commandLineBuffer.length} lines of message history`);
        break;

      case Command.USER:
        // User command completed
        if (messageContent.trim()) {
          this.addToChatMessageBuffer(messageContent);
        }
        break;

      case Command.NONE:
      case Command.PASSWORD:
        // Shouldn't happen, but just in case
        break;
    }

    // Reset command state before processing queue to allow new commands
    this.currentCommand = Command.NONE;
    this.commandLineBuffer = [];

    // Process any queued commands
    if (this.commandQueue.length > 0) {
      this.processCommandQueue();
    }
  }

  /**
   * Add message to chat message buffer for processing
   */
  private addToChatMessageBuffer(message: string): void {
    // This would normally be added to a chat message queue
    // For our purposes, we just need to know we received something
  }

  /**
   * Check if a line matches the chat message pattern
   */
  private isChatMessage(line: string): boolean {
    // Pattern: HHMMZ SENDER>MESSAGE
    const pattern = /^([0-9]{4})Z (.*)>(.*)$/;
    return pattern.test(line);
  }

  /**
   * Handle a chat message line
   */
  private handleChatMessage(line: string): void {
    const match = line.match(/^([0-9]{4})Z (.*)>(.*)$/);
    if (!match) {
      log.warn(`[CHAT] Regex failed for presumed chat line: "${line}"`);
      return;
    }

    const [, time, sender, message] = match;

    log.debug(`[CHAT] Parsed: time=${time}, sender="${sender.trim()}", message="${message.trim().substring(0,60)}..."`);

    // Create chat message object
    const chatMessage: ChatMessage = {
      time: time, // HHMM format (UTC)
      sender: sender.trim(),
      message: message.startsWith(' ') ? message.substring(1) : message, // Remove leading space if present
    };

    // Deduplication: generate a unique ID for this message
    const messageId = `${time}|${chatMessage.sender}|${chatMessage.message}`;
    log.debug(`[CHAT] DEDUP CHECK: id="${messageId.substring(0, 60)}..." cacheSize=${this.recentMessageIds.size} has=${this.recentMessageIds.has(messageId)}`);
    if (this.recentMessageIds.has(messageId)) {
      log.info(`[CHAT] Duplicate message ignored: ${messageId.substring(0, 80)}...`);
      return;
    }

    // Add to recent messages and trim if needed
    this.recentMessageIds.add(messageId);
    log.debug(`[CHAT] Added to dedup cache. New size: ${this.recentMessageIds.size}`);
    if (this.recentMessageIds.size > this.maxRecentMessages) {
      const first = this.recentMessageIds.values().next().value;
      if (first) {
        this.recentMessageIds.delete(first);
      }
    }

    // Notify listeners
    if (this.onMessageReceived) {
      log.debug(`[CHAT] Delivering to listener: ${JSON.stringify(chatMessage)}`);
      this.onMessageReceived(chatMessage);
    } else {
      log.warn('[CHAT] No message received callback registered!');
    }
  }

  /**
   * Handle connection errors
   */
  private handleError(error: Error): void {
    log.error(`Error: ${error.message}`);

    if (this.onError) {
      this.onError(error);
    }
  }

  /**
   * Attempt to reconnect with exponential backoff.
   * 5s → 10s → 15s → 20s → 25s → 30s (forever).
   * Reconnect attempts reset to 0 on successful login.
   */
  private attemptReconnect(): void {
    // Clear any existing reconnect timer to prevent duplicates
    this.clearReconnectTimer();

    // Calculate delay with exponential backoff, capped at maxReconnectDelay
    const delay = Math.min(
      this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts),
      this.maxReconnectDelay
    );

    log.info(`Scheduling reconnect in ${delay}ms (attempt ${this.reconnectAttempts + 1})`);

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.reconnectAttempts++;
      log.info(`Executing reconnect attempt ${this.reconnectAttempts}`);

      this.connect().catch((err) => {
        log.error(`Reconnection attempt failed: ${err.message}`);
        // Schedule another reconnect — retry forever
        this.attemptReconnect();
      });
    }, delay);
  }

  /**
   * Clear reconnect timer without clearing shouldReconnect flag
   */
  private clearReconnectTimer(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  // ─── Liveness Detection ───────────────────────────────────────

  /**
   * Start periodic liveness checks.
   * If no data is received for livenessTimeoutMs (90s), the connection
   * is declared dead and reconnection is triggered.
   */
  private startLivenessMonitor(): void {
    this.stopLivenessMonitor();
    this.lastDataTimestamp = Date.now();

    this.livenessTimer = setInterval(() => {
      this.checkLiveness();
    }, this.livenessCheckIntervalMs);

    log.debug(`Liveness monitor started: check every ${this.livenessCheckIntervalMs}ms, timeout ${this.livenessTimeoutMs}ms`);
  }

  /**
   * Stop liveness monitoring
   */
  private stopLivenessMonitor(): void {
    if (this.livenessTimer) {
      clearInterval(this.livenessTimer);
      this.livenessTimer = null;
    }
  }

  /**
   * Check if connection is still alive.
   * Called periodically by the liveness timer.
   */
  private checkLiveness(): void {
    if (!this.isConnected) {
      log.debug('Liveness check skipped: not connected');
      return;
    }

    const msSinceLastData = Date.now() - this.lastDataTimestamp;
    if (msSinceLastData > this.livenessTimeoutMs) {
      log.warn(`Connection declared DEAD: no data for ${msSinceLastData}ms (threshold: ${this.livenessTimeoutMs}ms). Forcing reconnect.`);

      // Mark as disconnected and force reconnect
      this.isConnected = false;
      this.isLoggedIn = false;
      this.stopLivenessMonitor();

      // Kill the stale socket
      if (this.connection) {
        this.connection.removeAllListeners();
        this.connection.destroy();
        this.connection = null;
      }

      // Notify status change
      if (this.onConnectionStatusChange) {
        this.onConnectionStatusChange(false);
      }

      // Trigger reconnection (does not reset exponential backoff counter)
      this.attemptReconnect();
    } else {
      log.debug(`Liveness OK: last data ${msSinceLastData}ms ago`);
    }
  }

  /**
   * Check if we're currently connected
   */
  isConnectedStatus(): boolean {
    return this.isConnected && this.connection !== null && this.connection.writable;
  }

  /**
   * Get diagnostic information about this connection
   */
  getDebugState(): any {
    const msSinceLastData = this.lastDataTimestamp ? Date.now() - this.lastDataTimestamp : 0;
    return {
      username: this.username,
      isConnected: this.isConnected,
      isLoggedIn: this.isLoggedIn,
      isWaitingForLoginPrompt: this.isWaitingForLoginPrompt,
      currentCommand: this.currentCommand,
      currentRoom: this.getRoomName(),
      reconnectAttempts: this.reconnectAttempts,
      reconnectDelay: Math.min(
        this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts),
        this.maxReconnectDelay
      ),
      bufferLength: this.receiveBuffer.length,
      shouldReconnect: this.shouldReconnect,
      liveness: {
        msSinceLastData,
        thresholdMs: this.livenessTimeoutMs,
        alive: msSinceLastData < this.livenessTimeoutMs,
        monitorRunning: this.livenessTimer !== null
      },
      lastMessages: [...this.lastMessages],
      stats: { ...this.diagnosticStats }
    };
  }

  /**
   * Append a message to the recent messages ring buffer
   */
  private addToRecentMessage(logLine: string): void {
    this.lastMessages.push(logLine);
    if (this.lastMessages.length > 20) {
      this.lastMessages.shift();
    }
  }
}

export default On4kstConnectionManager;
