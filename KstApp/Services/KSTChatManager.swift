import Foundation
import Network
import Combine
import SwiftUI
import UserNotifications
import UIKit

// MARK: - KST Chat Manager
class KSTChatManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    // MARK: - Constants
    private static let hostname = "www.on4kst.info"
    private static let port: UInt16 = 23000
    private static let updateUsersListInterval: TimeInterval = 3 * 60 // 3 minutes
    private static let secureStorageKey = "KST"
    private static let debugEnabled = false // Set to true to enable debug messages
    
    // MARK: - Debug Helper
    private func debugPrint(_ message: String) {
        if KSTChatManager.debugEnabled {
            print(message)
        }
    }
    
    // MARK: - Grid Square Validation
    func isValidGridSquare(_ gridSquare: String) -> Bool {
        guard gridSquare.count == 6 else { return false }
        
        let pattern = "^[A-Z]{2}[0-9]{2}[A-Z]{2}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: gridSquare.utf16.count)
        return regex?.firstMatch(in: gridSquare, options: [], range: range) != nil
    }
    
    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var chatMessages: [KSTChatMsg] = []
    @Published var usersList: [KSTUsersInfo] = []
    @Published var errorMessage: String?
    @Published var currentRoomIndex: Int = 1
    @Published var notificationsEnabled: Bool = true
    @Published var notificationFilter: NotificationFilter = .all
    @Published var myCallsign: String = ""
    @Published var myGridSquare: String = ""
    
    enum NotificationFilter: String, CaseIterable {
        case all = "All Messages"
        case myCallsign = "My Callsign Only"
        
        var displayName: String {
            return self.rawValue
        }
    }
    
    // MARK: - Computed Properties
    
    // MARK: - Private Properties
    private var tcpConnection: NWConnection?
    private var receiveBuffer = ""
    private var commandLineBuffer: [String] = []
    private var commandQueue: [(Command, String)] = []
    private var currentCommand: Command = .none
    private var updateUsersTimer: Timer?
    private var waitingForLoginPrompt = false
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 5
    private var reconnectDelay: TimeInterval = 5.0 // Start with 5 seconds
    private var storedUsername: String = ""
    private var storedPassword: String = ""
    private var storedRoomIndex: Int = 1
    private var storedGridSquare: String = ""
    private var lastMessageCount = 0
    private var isAppInBackground = false
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var backgroundConnectionTimer: Timer?
    private var userListTimeoutTimer: Timer?
    private var backgroundTaskRenewalTimer: Timer?
    private var isBackgroundTaskActive = false
    private var keepAliveTimer: Timer?
    
    // MARK: - Commands
    private enum Command {
        case none
        case login
        case user
        case showUsers
        case setGrid
        case showMessages
    }
    
    // MARK: - Chat Rooms
    static let chatRooms = [
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
    ]
    
    // MARK: - User Credentials
    private var username: String = ""
    private var password: String = ""
    
    // MARK: - Initialization
    override init() {
        super.init()
        loadCredentials()
        setupNotifications()
        setupAppStateObservers()
    }
    
    deinit {
        disconnectChat()
    }
    
    // MARK: - Public Methods
    func connectChat(roomIndex: Int, username: String, password: String, gridSquare: String = "") {
        self.currentRoomIndex = roomIndex
        self.username = username
        self.password = password
        self.myCallsign = username.uppercased() // Set myCallsign to uppercase username
        self.myGridSquare = gridSquare.uppercased() // Set grid square to uppercase
        
        
        // Update highlight rules with the new callsign
        let ruleManager = ChatHighlightRuleManager()
        ruleManager.updateMyCallsignRule(callsign: username)
        
        // Store connection parameters for reconnection
        self.storedRoomIndex = roomIndex
        self.storedUsername = username
        self.storedPassword = password
        self.storedGridSquare = gridSquare
        
        saveCredentials(username: username, password: password, roomIndex: roomIndex, gridSquare: gridSquare)
        connectToServer()
    }
    
    func disconnectChat() {
        updateUsersTimer?.invalidate()
        updateUsersTimer = nil
        userListTimeoutTimer?.invalidate()
        userListTimeoutTimer = nil
        
        tcpConnection?.cancel()
        tcpConnection = nil
        
        currentCommand = .none
        commandQueue.removeAll()
        receiveBuffer = ""
        commandLineBuffer.removeAll()
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
        
        // Start automatic reconnection if we have stored credentials
        startAutomaticReconnection()
    }
    
    func disconnectChat(manual: Bool) {
        updateUsersTimer?.invalidate()
        updateUsersTimer = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        
        tcpConnection?.cancel()
        tcpConnection = nil
        
        currentCommand = .none
        commandQueue.removeAll()
        receiveBuffer = ""
        commandLineBuffer.removeAll()
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
        
        if manual {
            // Stop reconnection if manually disconnected
            stopAutomaticReconnection()
        } else {
            // Start automatic reconnection if disconnected due to network issues
            startAutomaticReconnection()
        }
    }
    
    func clearChatData() {
        chatMessages.removeAll()
        usersList.removeAll()
        errorMessage = nil
        lastMessageCount = 0
    }
    
    func sendMessage(_ message: String) {
        guard !message.isEmpty else { return }
        
        debugPrint("Sending message: \(message)")
        
        if message.lowercased().hasPrefix("/chat") {
            DispatchQueue.main.async {
                self.errorMessage = "Changing chat is not supported"
            }
            return
        }
        
        // For regular messages, just send them directly without a command type
        if message.hasPrefix("/") {
            sendCommand(.user, message)
        } else {
            // Regular chat message - send directly
            sendCommand(.none, message)
        }
    }
    
    func getUserInfo(for callsign: String) -> KSTUsersInfo? {
        return usersList.first { $0.callsign == callsign }
    }
    
    func resetDupe() {
        for i in 0..<usersList.count {
            usersList[i] = KSTUsersInfo(
                callsign: usersList[i].callsign,
                grid: usersList[i].grid
            )
        }
    }
    
    // MARK: - Private Methods
    private func connectToServer() {
        debugPrint("Connecting to KST server at \(KSTChatManager.hostname):\(KSTChatManager.port)")
        
        let host = NWEndpoint.Host(KSTChatManager.hostname)
        let port = NWEndpoint.Port(integerLiteral: KSTChatManager.port)
        
        tcpConnection = NWConnection(host: host, port: port, using: .tcp)
        
        tcpConnection?.stateUpdateHandler = { [weak self] state in
            self?.debugPrint("Connection state changed: \(state)")
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.debugPrint("Connected to KST server")
                    self?.isConnected = true
                    self?.setupKeepAlive()
                    self?.sendLoginCommand()
                case .failed(let error):
                    self?.debugPrint("Connection failed: \(error)")
                    self?.isConnected = false
                    self?.errorMessage = "Connection failed: \(error.localizedDescription)"
                    self?.onReconnectionFailure() // Handle reconnection failure
                case .cancelled:
                    self?.debugPrint("Connection cancelled")
                    self?.isConnected = false
                default:
                    break
                }
            }
        }
        
        startReceiving()
        
        tcpConnection?.start(queue: .global(qos: .userInitiated))
    }
    
    private func setupKeepAlive() {
        // Send periodic keep-alive messages to prevent connection timeout
        // Use shorter interval in background to maintain connection
        let interval: TimeInterval = isAppInBackground ? 30.0 : 60.0
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendKeepAlive()
        }
    }
    
    private func sendKeepAlive() {
        guard isConnected else { return }
        
        // Send a simple ping to keep the connection alive
        sendCommand(.user, "")
        debugPrint("Sent keep-alive ping")
    }
    
    private func updateKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        if isConnected {
            setupKeepAlive()
        }
    }
    
    private func startReceiving() {
        tcpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.debugPrint("Received \(data.count) bytes from server")
                self?.processReceivedData(data)
            }
            
            if let error = error {
                self?.debugPrint("Receive error: \(error.localizedDescription)")
                return
            }
            
            if isComplete {
                self?.debugPrint("Connection completed")
                self?.disconnectChat()
                return
            }
            
            // Continue receiving
            self?.debugPrint("Continuing to receive data...")
            self?.startReceiving()
        }
    }
    
    private func processReceivedData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        debugPrint("Received data: '\(string)'")
        receiveBuffer += string
        let lines = joinLines()
        
        debugPrint("Processing \(lines.count) lines from received data")
        for line in lines {
            debugPrint("Processing line: \(line)")
            processLine(line)
        }
        
        // Check if we're still waiting for Login: prompt and have more data
        if waitingForLoginPrompt && !receiveBuffer.isEmpty {
            debugPrint("Still waiting for Login: prompt, remaining buffer: '\(receiveBuffer)'")
        }
    }
    
    private func joinLines() -> [String] {
        var lines: [String] = []
        
        debugPrint("Processing receiveBuffer: '\(receiveBuffer)'")
        
        // Handle both \n and \r\n line endings
        let components = receiveBuffer.components(separatedBy: .newlines)
        
        if components.count > 1 {
            // We have complete lines
            for i in 0..<components.count - 1 {
                let line = components[i].trimmingCharacters(in: .whitespacesAndNewlines)
                debugPrint("Extracted line: '\(line)'")
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            // Keep the last component (incomplete line) in the buffer
            receiveBuffer = components.last ?? ""
        }
        
        debugPrint("Remaining buffer: '\(receiveBuffer)'")
        return lines
    }
    
    private func processLine(_ line: String) {
        debugPrint("Processing line: '\(line)' (length: \(line.count))")
        
        guard !line.isEmpty else { 
            debugPrint("Skipping empty line")
            return 
        }
        
        if line.hasPrefix("Login:") {
            debugPrint("Server requesting login")
            waitingForLoginPrompt = false
            currentCommand = .login
            sendCommand(.login, username)
        } else if line.hasPrefix("Password:") {
            debugPrint("Server requesting password")
            sendCommand(.login, password)
        } else if line.hasPrefix("Your choice           :") {
            debugPrint("Server requesting room choice")
            sendCommand(.login, String(currentRoomIndex))
        } else if line.hasPrefix("Unknown user") {
            debugPrint("Unknown user error")
            waitingForLoginPrompt = false
            DispatchQueue.main.async {
                self.errorMessage = "Unknown User"
            }
            disconnectChat()
        } else if line.hasPrefix("Wrong password!") {
            debugPrint("Wrong password error")
            waitingForLoginPrompt = false
            DispatchQueue.main.async {
                self.errorMessage = "Invalid password"
            }
            disconnectChat()
        } else if currentCommand == .login && line.contains("chat>") {
            // Login completed - this is the final response from the server
            debugPrint("Login command completed")
            waitingForLoginPrompt = false
            DispatchQueue.main.async {
                self.isConnected = true
            }
            debugPrint("Sending commands after login completion")
            sendSetGridCommand()
            sendShowUsersCommand()
            sendShowMessagesCommand()
            currentCommand = .none
        } else if waitingForLoginPrompt {
            debugPrint("Waiting for Login: prompt, ignoring line: \(line)")
        } else {
            processChatLine(line)
        }
    }
    
    private func processChatLine(_ line: String) {
        debugPrint("Processing line: \(line)")
        
        let chatName = KSTChatManager.chatRooms[currentRoomIndex - 1]
        let chatCMDEndPattern = "([0-9]{4})Z \(username.uppercased()) \(NSRegularExpression.escapedPattern(for: chatName)) chat>(.*)"
        
        debugPrint("Checking if line matches command end pattern: '\(line)'")
        debugPrint("Pattern: \(chatCMDEndPattern)")
        
        if let regex = try? NSRegularExpression(pattern: chatCMDEndPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.range.location != NSNotFound {
            
            debugPrint("Command end detected for command: \(currentCommand)")
            
            // Command end detected - only add to chat messages for certain commands
            switch currentCommand {
            case .login:
                debugPrint("Login command completed")
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                onReconnectionSuccess() // Handle reconnection success
                sendSetGridCommand()
                sendShowUsersCommand()
                sendShowMessagesCommand()
                
                // Add login completion message to chat
                let message = KSTChatMsg(
                    time: DateFormatter.timeFormatter.string(from: Date()),
                    sender: "",
                    message: commandLineBuffer.joined(separator: "\n")
                )
                DispatchQueue.main.async {
                    self.chatMessages.append(message)
                }
            case .setGrid:
                debugPrint("Set grid command completed")
                // Add set grid completion message to chat
                let message = KSTChatMsg(
                    time: DateFormatter.timeFormatter.string(from: Date()),
                    sender: "",
                    message: commandLineBuffer.joined(separator: "\n")
                )
                DispatchQueue.main.async {
                    self.chatMessages.append(message)
                }
            case .showUsers:
                debugPrint("Show users command completed, processing \(commandLineBuffer.count) lines")
                userListTimeoutTimer?.invalidate()
                userListTimeoutTimer = nil
                finalizeShowUsersCommand(commandLineBuffer)
                // Don't add user list to chat messages
            case .showMessages:
                debugPrint("Show messages command completed, processing \(commandLineBuffer.count) lines")
                finalizeShowMessagesCommand(commandLineBuffer)
                // Don't add message history to chat messages (already processed)
            case .user:
                debugPrint("User command completed")
                // Add user command message to chat
                let message = KSTChatMsg(
                    time: DateFormatter.timeFormatter.string(from: Date()),
                    sender: "",
                    message: commandLineBuffer.joined(separator: "\n")
                )
                DispatchQueue.main.async {
                    self.chatMessages.append(message)
                }
            case .none:
                break
            }
            
            currentCommand = .none
            commandLineBuffer.removeAll()
            
            if !commandQueue.isEmpty {
                let (command, message) = commandQueue.removeFirst()
                sendCommand(command, message)
            }
        } else {
            debugPrint("Line does not match command end pattern, checking for chat message")
            // Check for regular chat message
            let chatLinePattern = "([0-9]{4})Z (.*)>(.*)"
            if let regex = try? NSRegularExpression(pattern: chatLinePattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               match.numberOfRanges >= 4 {
                
                let sender = String(line[Range(match.range(at: 2), in: line)!])
                let message = String(line[Range(match.range(at: 3), in: line)!])
                let grid = getUserInfo(for: sender)?.grid ?? Gridsquare()
                
                let chatMsg = KSTChatMsg(
                    time: DateFormatter.timeFormatter.string(from: Date()),
                    sender: sender,
                    message: message,
                    grid: grid
                )
                
                debugPrint("Chat message from \(sender): \(message)")
                
                DispatchQueue.main.async {
                    self.chatMessages.append(chatMsg)
                    // Send notification for new chat message
                    self.sendNotificationForNewMessage(chatMsg)
                }
            } else {
                if currentCommand != .none {
                    debugPrint("Adding to command buffer: \(line) (current command: \(currentCommand))")
                    commandLineBuffer.append(line)
                    debugPrint("Command buffer now has \(commandLineBuffer.count) lines")
                } else {
                    // Check if this looks like user list data (callsign + grid + name)
                    let userListPattern = "^(\\S{3,})\\s{1,}(\\S+)\\s(.*)$"
                    if let regex = try? NSRegularExpression(pattern: userListPattern),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       match.numberOfRanges >= 4 {
                        debugPrint("Detected user list data outside of command context: \(line)")
                        // Process this as a standalone user list entry
                        processUserListLine(line)
                    } else {
                        debugPrint("Unrecognized line: \(line)")
                    }
                }
            }
        }
    }
    
    private func processUserListLine(_ line: String) {
        let recordPattern = "^(\\S{3,})\\s{1,}(\\S+)\\s(.*)$"
        
        if let regex = try? NSRegularExpression(pattern: recordPattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           match.numberOfRanges >= 4 {
            
            let callsign = String(line[Range(match.range(at: 1), in: line)!]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            let gridString = String(line[Range(match.range(at: 2), in: line)!])
            let stationComment = String(line[Range(match.range(at: 3), in: line)!])
            
            debugPrint("Processing standalone user: callsign='\(callsign)', grid='\(gridString)', comment='\(stationComment)'")
            
            let user = KSTUsersInfo(
                callsign: callsign,
                grid: Gridsquare(grid: gridString)
            )
            
            DispatchQueue.main.async {
                // Check if user already exists, if not add them
                if !self.usersList.contains(where: { $0.callsign == user.callsign }) {
                    self.usersList.append(user)
                    self.debugPrint("Added user to list: \(user.callsign), total users: \(self.usersList.count)")
                } else {
                    self.debugPrint("User already exists: \(user.callsign)")
                }
            }
        }
    }
    
    private func sendCommand(_ command: Command, _ message: String) {
        debugPrint("Sending command: \(command) with message: \(message)")
        
        if currentCommand != .none && currentCommand != .login {
            debugPrint("Command queue full, adding to queue")
            commandQueue.append((command, message))
            return
        }
        
        // For .none commands (regular messages), don't set currentCommand
        if command != .none {
            currentCommand = command
            commandLineBuffer.removeAll()
        }
        
        guard let connection = tcpConnection else { 
            debugPrint("No TCP connection available")
            return 
        }
        
        let data = (message + "\r\n").data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.debugPrint("Error sending command: \(error)")
                DispatchQueue.main.async {
                    self.errorMessage = "Send error: \(error.localizedDescription)"
                }
            } else {
                self.debugPrint("Command sent successfully")
            }
        })
    }
    
    private func sendLoginCommand() {
        debugPrint("Starting login sequence")
        waitingForLoginPrompt = true
        currentCommand = .login
        
        // Set a timeout to wait for the Login: prompt
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.waitingForLoginPrompt == true {
                self?.debugPrint("Login timeout - server may not have sent Login: prompt, trying to send username anyway")
                self?.waitingForLoginPrompt = false
                self?.sendCommand(.login, self?.username ?? "")
            }
        }
    }
    
    private func sendSetGridCommand() {
        // Use the stored grid square, or skip if empty
        guard !myGridSquare.isEmpty else {
            debugPrint("No grid square set, skipping grid command")
            return
        }
        debugPrint("Sending set grid command with grid: \(myGridSquare)")
        sendCommand(.setGrid, "/set qra \(myGridSquare)")
    }
    
    private func sendShowUsersCommand() {
        debugPrint("Sending show users command")
        // Clear existing user list before fetching new data
        DispatchQueue.main.async {
            self.usersList.removeAll()
            self.debugPrint("Cleared existing user list")
        }
        
        // Start timeout timer in case command doesn't complete properly
        userListTimeoutTimer?.invalidate()
        userListTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.debugPrint("User list command timeout - processing any accumulated data")
            // The individual user processing should have already handled the data
        }
        
        sendCommand(.showUsers, "/sh us")
    }
    
    private func sendShowMessagesCommand() {
        debugPrint("Sending show messages command")
        sendCommand(.showMessages, "/show msg 50")
    }
    
    private func finalizeShowUsersCommand(_ buffer: [String]) {
        let recordPattern = "^(\\S{3,})\\s{1,}(\\S+)\\s(.*)$"
        
        debugPrint("Processing user list buffer with \(buffer.count) records:")
        for (index, record) in buffer.enumerated() {
            debugPrint("Record \(index): '\(record)'")
        }
        
        var newUsersList: [KSTUsersInfo] = []
        
        for record in buffer {
            if let regex = try? NSRegularExpression(pattern: recordPattern),
               let match = regex.firstMatch(in: record, range: NSRange(record.startIndex..., in: record)),
               match.numberOfRanges >= 4 {
                
                let callsign = String(record[Range(match.range(at: 1), in: record)!]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                let gridString = String(record[Range(match.range(at: 2), in: record)!])
                let stationComment = String(record[Range(match.range(at: 3), in: record)!])
                
                debugPrint("Parsed user: callsign='\(callsign)', grid='\(gridString)', comment='\(stationComment)'")
                
                let user = KSTUsersInfo(
                    callsign: callsign,
                    grid: Gridsquare(grid: gridString)
                )
                
                newUsersList.append(user)
            } else {
                debugPrint("Record does not match pattern: '\(record)'")
            }
        }
        
        debugPrint("Parsed \(newUsersList.count) users from \(buffer.count) records")
        
        DispatchQueue.main.async {
            self.debugPrint("Updating usersList with \(newUsersList.count) users")
            self.usersList = newUsersList
            self.debugPrint("usersList now contains \(self.usersList.count) users")
        }
        
        // Schedule next update
        updateUsersTimer = Timer.scheduledTimer(withTimeInterval: KSTChatManager.updateUsersListInterval, repeats: false) { [weak self] _ in
            self?.sendShowUsersCommand()
        }
    }
    
    private func finalizeShowMessagesCommand(_ buffer: [String]) {
        debugPrint("Processing message history buffer with \(buffer.count) records:")
        
        // Debug: Print all received records
        for (index, record) in buffer.enumerated() {
            debugPrint("Record \(index): '\(record)'")
        }
        
        var newMessages: [KSTChatMsg] = []
        
        for record in buffer {
            debugPrint("Processing message record: '\(record)'")
            
            // Parse message format: "HHMMZ SENDER>MESSAGE"
            let messagePattern = "([0-9]{4})Z (.*)>(.*)"
            if let regex = try? NSRegularExpression(pattern: messagePattern),
               let match = regex.firstMatch(in: record, range: NSRange(record.startIndex..., in: record)),
               match.numberOfRanges >= 4 {
                
                let time = String(record[Range(match.range(at: 1), in: record)!])
                let sender = String(record[Range(match.range(at: 2), in: record)!])
                let message = String(record[Range(match.range(at: 3), in: record)!])
                
                debugPrint("Parsed message: time='\(time)', sender='\(sender)', message='\(message)'")
                
                let chatMsg = KSTChatMsg(
                    time: time,
                    sender: sender,
                    message: message,
                    grid: Gridsquare() // Grid will be empty for historical messages
                )
                
                newMessages.append(chatMsg)
            } else {
                debugPrint("Message record does not match pattern: '\(record)'")
            }
        }
        
        debugPrint("Parsed \(newMessages.count) messages from \(buffer.count) records")
        
        // Add messages to the beginning of the chat (historical messages)
        DispatchQueue.main.async {
            self.chatMessages = newMessages + self.chatMessages
            // Update lastMessageCount to prevent notifications for historical messages
            self.lastMessageCount = self.chatMessages.count
        }
    }
    
    // MARK: - Automatic Reconnection
    private func startAutomaticReconnection() {
        // Only attempt reconnection if we have stored credentials and haven't exceeded max attempts
        guard !storedUsername.isEmpty && !storedPassword.isEmpty && reconnectAttempts < maxReconnectAttempts else {
            debugPrint("Reconnection stopped: no credentials or max attempts reached")
            return
        }
        
        reconnectAttempts += 1
        debugPrint("Starting automatic reconnection attempt \(reconnectAttempts)/\(maxReconnectAttempts) in \(reconnectDelay) seconds")
        
        // Schedule reconnection with exponential backoff
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            self?.attemptReconnection()
        }
    }
    
    private func attemptReconnection() {
        debugPrint("Attempting reconnection...")
        
        // Reset connection state
        currentCommand = .none
        commandQueue.removeAll()
        receiveBuffer = ""
        commandLineBuffer.removeAll()
        waitingForLoginPrompt = false
        
        // Attempt to connect with stored credentials
        connectToServer()
    }
    
    private func stopAutomaticReconnection() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0
        reconnectDelay = 5.0 // Reset delay
    }
    
    private func onReconnectionSuccess() {
        debugPrint("Reconnection successful!")
        stopAutomaticReconnection()
        
        // Update connection parameters from stored values
        self.currentRoomIndex = storedRoomIndex
        self.username = storedUsername
        self.password = storedPassword
        self.myGridSquare = storedGridSquare
        
        // Send a notification that we reconnected
        if isAppInBackground {
            sendReconnectionNotification()
        }
    }
    
    private func sendReconnectionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "KST Chat"
        content.body = "Reconnected to chat server"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "reconnection-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.debugPrint("Failed to send reconnection notification: \(error)")
            }
        }
    }
    
    private func onReconnectionFailure() {
        debugPrint("Reconnection failed, will retry...")
        
        // Exponential backoff: double the delay for next attempt
        reconnectDelay = min(reconnectDelay * 2, 60.0) // Cap at 60 seconds
        
        // Schedule next reconnection attempt
        startAutomaticReconnection()
    }
    
    // MARK: - Push Notifications
    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
            }
            if let error = error {
                self.debugPrint("Notification permission error: \(error)")
            }
        }
    }
    
    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.isAppInBackground = true
            self.startBackgroundTask()
            self.updateKeepAliveTimer()
            self.startBackgroundConnectionTimer()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.isAppInBackground = false
            self.endBackgroundTask()
            self.updateKeepAliveTimer()
            self.startBackgroundConnectionTimer()
            // Reconnect if we were connected before going to background
            if self.isConnected {
                self.reconnectAfterBackground()
            }
        }
    }
    
    private func startBackgroundTask() {
        guard !isBackgroundTaskActive else { return }
        
        endBackgroundTask() // End any existing background task
        
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "KSTChatConnection") { [weak self] in
            // This block is called when the background task is about to expire
            self?.debugPrint("Background task expiring, attempting to renew...")
            self?.renewBackgroundTask()
        }
        
        isBackgroundTaskActive = true
        
        // Start a timer to periodically check connection in background
        startBackgroundConnectionTimer()
        
        // Start a timer to renew the background task before it expires
        startBackgroundTaskRenewalTimer()
        
        debugPrint("Started background task: \(backgroundTaskIdentifier.rawValue)")
    }
    
    private func startBackgroundConnectionTimer() {
        stopBackgroundConnectionTimer()
        
        // More frequent connection monitoring in background
        let interval: TimeInterval = isAppInBackground ? 15.0 : 30.0
        backgroundConnectionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            if self.isAppInBackground && self.isConnected {
                self.debugPrint("Background: Checking connection status...")
                self.sendPingToVerifyConnection()
            }
        }
    }
    
    private func stopBackgroundConnectionTimer() {
        backgroundConnectionTimer?.invalidate()
        backgroundConnectionTimer = nil
    }
    
    private func startBackgroundTaskRenewalTimer() {
        stopBackgroundTaskRenewalTimer()
        
        // Renew background task every 25 minutes (iOS gives ~30 minutes)
        backgroundTaskRenewalTimer = Timer.scheduledTimer(withTimeInterval: 25 * 60, repeats: true) { [weak self] _ in
            self?.renewBackgroundTask()
        }
    }
    
    private func stopBackgroundTaskRenewalTimer() {
        backgroundTaskRenewalTimer?.invalidate()
        backgroundTaskRenewalTimer = nil
    }
    
    private func renewBackgroundTask() {
        guard isAppInBackground && isConnected else {
            debugPrint("Not renewing background task - app not in background or not connected")
            return
        }
        
        // End current background task
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }
        
        // Start new background task
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "KSTChatConnection") { [weak self] in
            self?.debugPrint("Renewed background task expiring, attempting to renew again...")
            self?.renewBackgroundTask()
        }
        
        debugPrint("Renewed background task: \(backgroundTaskIdentifier.rawValue)")
    }
    
    private func endBackgroundTask() {
        stopBackgroundConnectionTimer()
        stopBackgroundTaskRenewalTimer()
        isBackgroundTaskActive = false
        
        if backgroundTaskIdentifier != .invalid {
            debugPrint("Ending background task: \(backgroundTaskIdentifier.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
    
    private func reconnectAfterBackground() {
        debugPrint("App returned to foreground, checking connection...")
        
        // Give the connection a moment to recover
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.isConnected {
                self.debugPrint("Connection lost during background, attempting to reconnect...")
                self.connectChat(roomIndex: self.storedRoomIndex, username: self.storedUsername, password: self.storedPassword, gridSquare: self.storedGridSquare)
            } else {
                self.debugPrint("Connection still active after background")
                // Send a ping to verify the connection is still working
                self.sendPingToVerifyConnection()
            }
        }
    }
    
    private func sendPingToVerifyConnection() {
        // Send a simple command to verify the connection is still working
        sendCommand(.user, "")
        
        // Set a timeout to detect if we don't get a response
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.isAppInBackground && self.isConnected {
                self.debugPrint("Background: No response to ping, connection may be lost")
                self.handleConnectionLoss()
            }
        }
    }
    
    private func handleConnectionLoss() {
        debugPrint("Connection lost during background")
        isConnected = false
        
        // If we're in background, start reconnection attempts
        if isAppInBackground {
            startAutomaticReconnection()
        }
    }
    
    private func sendNotificationForNewMessage(_ message: KSTChatMsg) {
        guard notificationsEnabled && isAppInBackground else { return }
        
        // Only send notifications for messages that are truly new (not historical)
        // Check if this message was added after the last known message count
        if chatMessages.count <= lastMessageCount {
            debugPrint("Skipping notification for historical message: \(message.message)")
            return
        }
        
        // Update the last message count
        lastMessageCount = chatMessages.count
        
        // Check notification filter
        if notificationFilter == .myCallsign {
            // Check if message contains my callsign in parentheses (case insensitive)
            let messageText = message.message.uppercased()
            let myCallsignUpper = myCallsign.uppercased()
            let pattern = "\\(\(myCallsignUpper)\\)"
            
            if !messageText.contains(pattern) {
                debugPrint("Notification filtered out - message doesn't contain my callsign: \(messageText)")
                return
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = "ON4KST Chat"
        content.body = "\(message.sender): \(message.message)"
        content.sound = .default
        content.badge = NSNumber(value: chatMessages.count)
        
        // Add message data for potential deep linking
        content.userInfo = [
            "sender": message.sender,
            "message": message.message,
            "time": message.time
        ]
        
        let request = UNNotificationRequest(
            identifier: "chat_message_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.debugPrint("Failed to send notification: \(error)")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap - could implement deep linking here
        debugPrint("Notification tapped: \(response.notification.request.content.userInfo)")
        completionHandler()
    }
    
    // MARK: - Credential Management
    func loadCredentials() {
        username = UserDefaults.standard.string(forKey: "KSTUsername") ?? ""
        password = UserDefaults.standard.string(forKey: "KSTPassword") ?? ""
        myGridSquare = UserDefaults.standard.string(forKey: "KSTGridSquare") ?? ""
        currentRoomIndex = UserDefaults.standard.integer(forKey: "KSTRoomIndex")
        
        if currentRoomIndex <= 0 {
            currentRoomIndex = 1 // Default to first room
        }
        // Note: In a production app, password should be stored in Keychain
    }
    
    private func saveCredentials(username: String, password: String, roomIndex: Int, gridSquare: String = "") {
        UserDefaults.standard.set(username, forKey: "KSTUsername")
        UserDefaults.standard.set(password, forKey: "KSTPassword")
        UserDefaults.standard.set(roomIndex, forKey: "KSTRoomIndex")
        UserDefaults.standard.set(gridSquare, forKey: "KSTGridSquare")
        // Note: In a production app, password should be stored in Keychain
    }
}

// MARK: - DateFormatter Extension
private extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}

