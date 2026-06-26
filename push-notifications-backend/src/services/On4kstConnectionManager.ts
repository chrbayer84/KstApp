import net from 'net';
import { UserSettings } from '../models/UserSettings';
import UserSettingsService from './UserSettingsService';

// Message types
interface ChatMessage {
  time: string;     // HHMM format (UTC)
  sender: string;   // Callsign
  message: string;  // Message text
  grid?: string;    // Grid square (from user list)
}

interface CommandResponse {
  success: boolean;
  data?: string;
  error?: string;
}

// Command types that we send to the ON4 send to the ON4KST server
enum Command {
  LOGIN = 'login',
  PASSWORD = 'password',
  ROOM = 'room',
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
  private isWaitingForLoginPrompt: boolean = false;
  private updateUsersTimer: NodeJS.Timeout | null = null;
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 5;
  private reconnectDelay: number = 5000; // Start with 5 seconds
  
  // For storing user list (callsign -> grid mapping)
  private userList: Map<string, { grid: string; name: string }> = new Map();
  
  // Callbacks
  private onMessageReceived: ((message: ChatMessage) => void) | null = null;
  private onConnectionStatusChange: ((isConnected: boolean) => void) | null = null;
  private onError: ((error: Error) => void) | null = null;

  constructor(username: string) {
    this.username = username.toUpperCase(); // ON4KST uses uppercase callsigns
  }

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
      // Close any existing connection
      this.disconnect();

      // Create new connection
      this.connection = new net.Socket();
      
      this.connection.on('connect', () => {
        console.log(`[${this.username}] Connected to ON4KST server`);
        this.isWaitingForLoginPrompt = true;
        this.currentCommand = Command.LOGIN;
        this.commandLineBuffer = [];
        this.receiveBuffer = '';
        
        // Notify connection status change
        if (this.onConnectionStatusChange) {
          this.onConnectionStatusChange(true);
        }
        
        resolve();
      });

      this.connection.on('data', (data: Buffer) => {
        this.processReceivedData(data.toString('utf8'));
      });

      this.connection.on('error', (error: Error) => {
        console.error(`[${this.username}] Connection error:`, error);
        this.handleError(error);
        
        // Try to reconnect
        this.attemptReconnect(reject);
      });

      this.connection.on('close', (hadError: boolean) => {
        console.log(`[${this.username}] Connection closed${hadError ? ' with error' : ''}`);
        this.isConnected = false;
        
        // Notify connection status change
        if (this.onConnectionStatusChange) {
          this.onConnectionStatusChange(false);
        }
        
        // Clear timers
        if (this.updateUsersTimer) {
          clearInterval(this.updateUsersTimer);
          this.updateUsersTimer = null;
        }
        
        // Try to reconnect
        this.attemptReconnect(reject);
      });

      this.connection.connect({
        host: 'www.on4kst.info',
        port: 23000
      });
    });
  }

  /**
   * Disconnect from the ON4KST server
   */
  disconnect(): void {
    if (this.connection) {
      this.connection.destroy();
      this.connection = null;
    }
    
    // Clear timers
    if (this.updateUsersTimer) {
      clearInterval(this.updateUsersTimer);
      this.updateUsersTimer = null;
    }
    
    this.isConnected = false;
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
   * Send a command to the ON4KST server
   */
  private sendCommand(command: Command, message: string): Promise<CommandResponse> {
    return new Promise((resolve, reject) => {
      // If we're already processing a command (and it's not login), queue this one
      if (this.currentCommand !== Command.NONE && this.currentCommand !== Command.LOGIN) {
        this.commandQueue.push({ command, message, resolve, reject });
        return;
      }
      
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
      this.connection.write(data, (err) => {
        if (err) {
          reject(err);
        }
        // Resolution will happen when we receive the command completion signal
      });
    });
  }

  /**
   * Process incoming data from the socket
   */
  private processReceivedData(data: string): void {
    this.receiveBuffer += data;
    const lines = this.splitLines();
    
    for (const line of lines) {
      this.processLine(line.trim());
    }
    
    // Check if we're still waiting for login prompt and have more data
    if (this.isWaitingForLoginPrompt && this.receiveBuffer.length > 0) {
      // Keep waiting - the prompt might come in chunks
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
    
    // Debug logging
    // console.log(`[${this.username}] Received: "${line}"`);
    
    // Handle login prompts
    if (line.startsWith('Login:')) {
      this.isWaitingForLoginPrompt = false;
      if (this.settings) {
        this.sendCommand(Command.LOGIN, this.settings.username);
      }
      return;
    }
    
    if (line.startsWith('Password:')) {
      this.isWaitingForLoginPrompt = false;
      if (this.settings) {
        this.sendCommand(Command.PASSWORD, this.settings.password);
      }
      return;
    }
    
    if (line.startsWith('Your choice')) {
      this.isWaitingForLoginPrompt = false;
      // Default to room 1 (50/70 MHz) if not specified in settings
      // Note: We don't have currentRoomIndex in UserSettings, so we default to 1
      this.sendCommand(Command.ROOM, '1');
      return;
    }
    
    // Handle error messages
    if (line.startsWith('Unknown user')) {
      this.handleError(new Error('Unknown user'));
      return;
    }
    
    if (line.startsWith('Wrong password!')) {
      this.handleError(new Error('Invalid password'));
      return;
    }
    
    // Check for command completion
    if (this.isWaitingForResponse(line)) {
      this.handleCommandCompletion(line);
      return;
    }
    
    // If we're waiting for login prompt, ignore other lines
    if (this.isWaitingForLoginPrompt) {
      return;
    }
    
    // Check if this is a chat message
    if (this.isChatMessage(line)) {
      this.handleChatMessage(line);
      return;
    }
    
    // Check if this looks like user list data
    if (this.isUserListData(line)) {
      this.processUserListLine(line);
      return;
    }
    
    // If we're expecting a command response, add to buffer
    if (this.currentCommand !== Command.NONE) {
      this.commandLineBuffer.push(line);
      return;
    }
    
    // Unrecognized line
    console.log(`[${this.username}] Unrecognized line: "${line}"`);
  }

  /**
   * Check if we're waiting for a response to a command we sent
   */
  private isWaitingForResponse(line: string): boolean {
    // Pattern for command completion: HHMMZ <OUR_USERNAME> <ROOM_NAME> chat>...
    const roomName = this.getRoomName();
    const pattern = new RegExp(`^([0-9]{4})Z ${this.username} ${roomName} chat>.*$`);
    return pattern.test(line);
  }

  /**
   * Get the current room name based on settings
   */
  private getRoomName(): string {
    // We don't have currentRoomIndex in UserSettings, so we default to room 1
    const roomIndex = 1; // Default to first room (50/70 MHz)
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
    
    return rooms[roomIndex - 1] || rooms[0];
  }

  /**
   * Handle command completion
   */
  private handleCommandCompletion(line: string): void {
    // Extract the message part after "chat>"
    const match = line.match(/^([0-9]{4})Z [^>]+>chat>(.*)$/);
    const messageContent = match ? match[2] : '';
    
    let response: CommandResponse = { success: true, data: messageContent };
    
    // Process based on the command we were waiting for
    switch (this.currentCommand) {
      case Command.LOGIN:
        // Login completed successfully
        this.isConnected = true;
        this.reconnectAttempts = 0; // Reset reconnect counter on success
        this.startUserListUpdates();
        
        // Add login completion message to chat if there's content
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
        
      case Command.SHOW_USERS:
        // Process user list
        this.processUserListBuffer(this.commandLineBuffer);
        // Don't add user list to chat messages
        break;
        
      case Command.SHOW_MESSAGES:
        // Process message history (we don't notify on history)
        this.processMessageHistoryBuffer(this.commandLineBuffer);
        // Don't add message history to chat messages
        break;
        
      case Command.USER:
        // User command completed
        if (messageContent.trim()) {
          this.addToChatMessageBuffer(messageContent);
        }
        break;
        
      case Command.NONE:
        // Shouldn't happen, but just in case
        break;
    }
    
    // Resolve any waiting promise for this command
    if (this.commandQueue.length > 0) {
      const next = this.commandQueue.shift()!;
      next.resolve(response);
    }
    
    // Reset command state
    this.currentCommand = Command.NONE;
    this.commandLineBuffer = [];
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
      return;
    }
    
    const [, time, sender, message] = match;
    
    // Create chat message object
    const chatMessage: ChatMessage = {
      time: time, // HHMM format (UTC)
      sender: sender.trim(),
      message: message.startsWith(' ') ? message.substring(1) : message, // Remove leading space if present
    };
    
    // Notify listeners
    if (this.onMessageReceived) {
      this.onMessageReceived(chatMessage);
    }
  }

  /**
   * Check if a line looks like user list data
   */
  private isUserListData(line: string): boolean {
    // Pattern: CALLSIGN GRID COMMENT
    // Example: ON1ABC JO21xx Some comment here
    const pattern = /^(\S{3,})\s{1,}(\S+)\s(.*)$/;
    return pattern.test(line);
  }

  /**
   * Process a user list line
   */
  private processUserListLine(line: string): void {
    const match = line.match(/^(\S{3,})\s{1,}(\S+)\s(.*)$/);
    if (!match) {
      return;
    }
    
    const [, callsign, grid, comment] = match;
    
    // Store in our user list map
    this.userList.set(callsign.toUpperCase(), {
      grid: grid,
      name: comment.trim()
    });
  }

  /**
   * Process the user list buffer (from SHOW_USERS command)
   */
  private processUserListBuffer(buffer: string[]): void {
    // Clear existing user list
    this.userList.clear();
    
    // Process each line
    for (const line of buffer) {
      this.processUserListLine(line);
    }
    
    console.log(`[${this.username}] Updated user list: ${this.userList.size} users`);
  }

  /**
   * Process message history buffer (from SHOW_MESSAGES command)
   */
  private processMessageHistoryBuffer(buffer: string[]): void {
    // We don't store or process message history for notifications
    // Just consume it to keep the connection clean
    console.log(`[${this.username}] Processed ${buffer.length} lines of message history`);
  }

  /**
   * Start periodic user list updates
   */
  private startUserListUpdates(): void {
    // Clear any existing timer
    if (this.updateUsersTimer) {
      clearInterval(this.updateUsersTimer);
    }
    
    // Request user list every 3 minutes (as per the iOS app)
    this.updateUsersTimer = setInterval(() => {
      this.sendCommand(Command.SHOW_USERS, '/sh us');
    }, 3 * 60 * 1000); // 3 minutes in milliseconds
    
    // Also send immediately to get initial user list
    this.sendCommand(Command.SHOW_USERS, '/sh us');
  }

  /**
   * Handle connection errors
   */
  private handleError(error: Error): void {
    console.error(`[${this.username}] Error:`, error.message);
    
    if (this.onError) {
      this.onError(error);
    }
  }

  /**
   * Attempt to reconnect with exponential backoff
   */
  private attemptReconnect(reject: (reason?: any) => void): void {
    // Don't reconnect if we're already trying to connect or if we've maxed out attempts
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error(`[${this.username}] Max reconnect attempts reached. Giving up.`);
      if (this.onError) {
        this.onError(new Error('Max reconnect attempts reached'));
      }
      reject(new Error('Max reconnect attempts reached'));
      return;
    }
    
    // Calculate delay with exponential backoff
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts);
    this.reconnectAttempts++;
    
    console.log(`[${this.username}] Attempting to reconnect in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
    
    setTimeout(() => {
      this.connect().catch(reject);
    }, delay);
  }

  /**
   * Get grid square for a callsign from our user list
   */
  getGridForCallsign(callsign: string): string | undefined {
    const userInfo = this.userList.get(callsign.toUpperCase());
    return userInfo?.grid;
  }

  /**
   * Get callsign info (grid and name) from our user list
   */
  getUserInfo(callsign: string): { grid: string; name: string } | undefined {
    return this.userList.get(callsign.toUpperCase());
  }

  /**
   * Check if we're currently connected
   */
  isConnectedStatus(): boolean {
    return this.isConnected && this.connection !== null && this.connection.writable;
  }
}

export default On4kstConnectionManager;
