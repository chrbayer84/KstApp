import SwiftUI
import Foundation

struct KSTChatView: View {
    @StateObject private var chatManager = KSTChatManager()
    @StateObject private var highlightEvaluator = ChatHighlightEvaluator(roomIndex: 1)
    @State private var messageText = ""
    @State private var showingLogin = false
    @State private var selectedRoomIndex = 1
    @State private var username = ""
    @State private var password = ""
    @State private var selectedCallsign: String? = nil
    @State private var sortBy: SortOption = .callsign
    @State private var sortAscending: Bool = true
    @State private var gridSquare: String = ""
    @State private var isLandscape: Bool = false
    
    
    enum SortOption: CaseIterable {
        case callsign
        case grid
        case azimuth
        case distance
        
        var displayName: String {
            switch self {
            case .callsign: return "Callsign"
            case .grid: return "Grid"
            case .azimuth: return "Azimuth"
            case .distance: return "Distance"
            }
        }
    }
    
    private var sortedUsers: [KSTUsersInfo] {
        let sorted = chatManager.usersList.sorted { user1, user2 in
            let comparison: ComparisonResult
            switch sortBy {
            case .callsign:
                comparison = user1.callsign.localizedCaseInsensitiveCompare(user2.callsign)
            case .grid:
                comparison = user1.grid.grid.localizedCaseInsensitiveCompare(user2.grid.grid)
            case .azimuth:
                let azimuth1 = calculateAzimuth(for: user1)
                let azimuth2 = calculateAzimuth(for: user2)
                if azimuth1 == nil && azimuth2 == nil {
                    comparison = .orderedSame
                } else if azimuth1 == nil {
                    comparison = .orderedDescending
                } else if azimuth2 == nil {
                    comparison = .orderedAscending
                } else {
                    let a1 = azimuth1!
                    let a2 = azimuth2!
                    comparison = a1 < a2 ? .orderedAscending : (a1 > a2 ? .orderedDescending : .orderedSame)
                }
            case .distance:
                let distance1 = calculateDistance(for: user1)
                let distance2 = calculateDistance(for: user2)
                if distance1 == nil && distance2 == nil {
                    comparison = .orderedSame
                } else if distance1 == nil {
                    comparison = .orderedDescending
                } else if distance2 == nil {
                    comparison = .orderedAscending
                } else {
                    let d1 = distance1!
                    let d2 = distance2!
                    comparison = d1 < d2 ? .orderedAscending : (d1 > d2 ? .orderedDescending : .orderedSame)
                }
            }
            
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        return sorted
    }
    
    private func calculateAzimuth(for user: KSTUsersInfo) -> Double? {
        guard !chatManager.myGridSquare.isEmpty else { return nil }
        let myGrid = Gridsquare(grid: chatManager.myGridSquare)
        return myGrid.bearingTo(user.grid)
    }
    
    private func calculateDistance(for user: KSTUsersInfo) -> Double? {
        guard !chatManager.myGridSquare.isEmpty else { return nil }
        let myGrid = Gridsquare(grid: chatManager.myGridSquare)
        return myGrid.distanceTo(user.grid)
    }
    
    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                VStack(spacing: 0) {
                    // Header with room info and connection status
                    headerView
                    
                    // Main chat area
                    HStack(spacing: 0) {
                        // Chat messages
                        chatMessagesView
                            .frame(maxWidth: .infinity)
                        
                        // Users list
                        usersListView
                            .frame(width: isLandscape ? 220 : 180)
                            .background(Color(.systemGray6))
                    }
                    
                    // Message input
                    messageInputView
                }
            }
            .sheet(isPresented: $showingLogin) {
                loginView
            }
            .alert("Error", isPresented: .constant(chatManager.errorMessage != nil)) {
                Button("OK") {
                    chatManager.errorMessage = nil
                }
            } message: {
                Text(chatManager.errorMessage ?? "")
            }
            .onAppear {
                // Load credentials into chat manager first
                chatManager.loadCredentials()
                self.checkCredentialsAndShowLogin()
                
                // Detect initial orientation
                detectOrientation(geometry: geometry)
            }
            .onChange(of: geometry.size) {
                detectOrientation(geometry: geometry)
            }
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 8) {
            // Channel name - always visible
            Text("ON4KST Chat - \(KSTChatManager.chatRooms[chatManager.currentRoomIndex - 1])")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Status and controls row
            HStack {
                HStack {
                    Circle()
                        .fill(chatManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(chatManager.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Text("Users: \(chatManager.usersList.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        chatManager.notificationsEnabled.toggle()
                    }) {
                        Image(systemName: chatManager.notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                            .foregroundColor(chatManager.notificationsEnabled ? .blue : .gray)
                    }
                    .buttonStyle(.plain)
                    
                    if chatManager.isConnected {
                        Button("Disconnect") {
                            chatManager.disconnectChat(manual: true)
                            showingLogin = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Connect") {
                            showingLogin = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
    
    // MARK: - Chat Messages View
    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(chatManager.chatMessages.enumerated()), id: \.offset) { index, message in
                        ChatMessageRow(
                            message: message,
                            highlightResult: highlightEvaluator.shouldHighlight(message),
                            myCallsign: chatManager.myCallsign,
                            onCallsignTap: { callsign in
                                selectedCallsign = callsign
                            }
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: chatManager.chatMessages.count) {
                withAnimation {
                    proxy.scrollTo(chatManager.chatMessages.count - 1, anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - Users List View
    private var usersListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chatManager.usersList.isEmpty {
                Text("No users online")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            } else {
                VStack(spacing: 0) {
                    // Custom header
                    HStack {
                        Button(action: {
                            if sortBy == .callsign {
                                sortAscending.toggle()
                            } else {
                                sortBy = .callsign
                                sortAscending = true
                            }
                        }) {
                            HStack {
                                Text("Call")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(sortBy == .callsign ? .blue : .secondary)
                                
                                if sortBy == .callsign {
                                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .frame(width: 70, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        
                        Button(action: {
                            if sortBy == .grid {
                                sortAscending.toggle()
                            } else {
                                sortBy = .grid
                                sortAscending = true
                            }
                        }) {
                            HStack {
                                Text("Grid")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(sortBy == .grid ? .blue : .secondary)
                                
                                if sortBy == .grid {
                                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .frame(width: 45, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            if sortBy == .azimuth {
                                sortAscending.toggle()
                            } else {
                                sortBy = .azimuth
                                sortAscending = true
                            }
                        }) {
                            HStack {
                                Text("Az")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(sortBy == .azimuth ? .blue : .secondary)
                                
                                if sortBy == .azimuth {
                                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .frame(width: 35, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Distance column - only show in landscape
                        if isLandscape {
                            Button(action: {
                                if sortBy == .distance {
                                    sortAscending.toggle()
                                } else {
                                    sortBy = .distance
                                    sortAscending = true
                                }
                            }) {
                                HStack {
                                    Text("Dist")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(sortBy == .distance ? .blue : .secondary)
                                    
                                    if sortBy == .distance {
                                        Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }
                                .frame(width: 45, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(Color(.systemGray6))
                    
                    // User list
                    List(sortedUsers) { user in
                        HStack(spacing: 0) { // Remove spacing between columns
                            Button(action: {
                                selectedCallsign = user.callsign
                            }) {
                                Text(user.callsign)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .foregroundColor(selectedCallsign == user.callsign ? .blue : .primary)
                                    .frame(width: 70, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            
                            Text(user.grid.grid)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 45, alignment: .leading)
                            
                            Text(calculateAzimuth(for: user).map { "\(Int($0))°" } ?? "--")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 35, alignment: .leading)
                            
                            // Distance column - only show in landscape
                            if isLandscape {
                                Text(calculateDistance(for: user).map { String(format: "%.0f km", $0) } ?? "--")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 0.5)
                        .background(selectedCallsign == user.callsign ? Color.blue.opacity(0.1) : Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .padding(.horizontal, 0)
                    .padding(.vertical, 0)
                }
            }
        }
        .padding(0)
    }
    
    // MARK: - Message Input View
    private var messageInputView: some View {
        VStack(spacing: 8) {
            // Selected callsign label
            if let callsign = selectedCallsign {
                HStack {
                    Text(displayTextForCallsign(callsign))
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Button("Clear") {
                        selectedCallsign = nil
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            
            // Message input
            HStack {
                TextField("Type a message...", text: $messageText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendMessage()
                    }
                
                Button("Send") {
                    sendMessage()
                }
                .disabled(messageText.isEmpty || !chatManager.isConnected)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }
    
    // MARK: - Login View
    private var loginView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.headline)
                    TextField("Enter username", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grid Square")
                        .font(.headline)
                    TextField("e.g., JN79HK", text: $gridSquare)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                        .onChange(of: gridSquare) { _, newValue in
                            // Convert to uppercase and limit to 6 characters
                            gridSquare = String(newValue.uppercased().prefix(6))
                        }
                    
                    if !gridSquare.isEmpty && !chatManager.isValidGridSquare(gridSquare) {
                        Text("Grid square must be 6 characters: 2 letters, 2 numbers, 2 letters (e.g., JN79HK)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat Room")
                        .font(.headline)
                    Picker("Room", selection: $selectedRoomIndex) {
                        ForEach(1...KSTChatManager.chatRooms.count, id: \.self) { index in
                            Text(KSTChatManager.chatRooms[index - 1])
                                .tag(index)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Spacer()
                
                Button("Connect") {
                    chatManager.connectChat(
                        roomIndex: selectedRoomIndex,
                        username: username,
                        password: password,
                        gridSquare: gridSquare
                    )
                    showingLogin = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty || password.isEmpty || (!gridSquare.isEmpty && !chatManager.isValidGridSquare(gridSquare)))
            }
            .padding()
            .navigationTitle("KST Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        chatManager.clearChatData()
                        showingLogin = false
                    }
                }
            }
        }
    }
    
    
    // MARK: - Helper Methods
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let messageToSend: String
        if let callsign = selectedCallsign {
            messageToSend = "(\(callsign)) \(messageText)"
        } else {
            messageToSend = messageText
        }
        
        chatManager.sendMessage(messageToSend)
        messageText = ""
    }
    
    // MARK: - Private Methods
    private func detectOrientation(geometry: GeometryProxy) {
        isLandscape = geometry.size.width > geometry.size.height
    }
    
    private func displayTextForCallsign(_ callsign: String) -> String {
        let userInfo = chatManager.usersList.first { $0.callsign == callsign }
        let gridText = userInfo?.grid.grid ?? ""
        let nameText = userInfo?.name ?? ""
        
        if !nameText.isEmpty && !gridText.isEmpty {
            return "To: \(callsign) \(nameText) (\(gridText))"
        } else if !nameText.isEmpty {
            return "To: \(callsign) \(nameText)"
        } else if !gridText.isEmpty {
            return "To: \(callsign) (\(gridText))"
        } else {
            return "To: \(callsign)"
        }
    }
    
    private func checkCredentialsAndShowLogin() {
        // Check if we have stored credentials
        let storedUsername = UserDefaults.standard.string(forKey: "KSTUsername") ?? ""
        let storedPassword = UserDefaults.standard.string(forKey: "KSTPassword") ?? ""
        let storedRoomIndex = UserDefaults.standard.integer(forKey: "KSTRoomIndex")
        let storedGridSquare = UserDefaults.standard.string(forKey: "KSTGridSquare") ?? ""
        
        
        // If no credentials are stored, show login screen
        if storedUsername.isEmpty || storedPassword.isEmpty {
            self.showingLogin = true
        } else {
            // Load stored credentials and auto-connect
            self.username = storedUsername
            self.password = storedPassword
            self.gridSquare = storedGridSquare
            self.selectedRoomIndex = storedRoomIndex > 0 ? storedRoomIndex : 1
            
            // Auto-connect to the last room
            print("Auto-connecting with stored credentials to room \(selectedRoomIndex)")
            chatManager.connectChat(roomIndex: selectedRoomIndex, username: storedUsername, password: storedPassword, gridSquare: storedGridSquare)
        }
    }
}

// MARK: - Chat Message Row
struct ChatMessageRow: View {
    let message: KSTChatMsg
    let highlightResult: (shouldHighlight: Bool, matchedRules: [String])
    let myCallsign: String
    let onCallsignTap: (String) -> Void
    
    private var isDirectedToMe: Bool {
        guard !myCallsign.isEmpty else { return false }
        let messageText = message.message.uppercased()
        let myCallsignUpper = myCallsign.uppercased()
        return messageText.contains(myCallsignUpper)
    }
    
    private var isFromMe: Bool {
        guard !myCallsign.isEmpty else { return false }
        return message.sender.uppercased() == myCallsign.uppercased()
    }
    
    private var shouldHighlight: Bool {
        return highlightResult.shouldHighlight || isDirectedToMe
    }
    
    private var shouldHighlightGreen: Bool {
        return isFromMe
    }
    
    // Helper to create attributed string with clickable links
    private var attributedMessage: AttributedString {
        var attributedString = AttributedString(message.message)
        
        // Use NSDataDetector to find URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: message.message.utf16.count)
        
        if let matches = detector?.matches(in: message.message, options: [], range: range) {
            // Process matches in reverse order to maintain correct indices
            for match in matches.reversed() {
                if let url = match.url,
                   let swiftRange = Range(match.range, in: message.message) {
                    let attributedRange = Range(swiftRange, in: attributedString)
                    if let attributedRange = attributedRange {
                        attributedString[attributedRange].link = url
                        attributedString[attributedRange].foregroundColor = .blue
                        attributedString[attributedRange].underlineStyle = .single
                    }
                }
            }
        }
        
        return attributedString
    }
    
    // Extract just the callsign (first word) from sender string
    private var callsignOnly: String {
        let trimmed = message.sender.trimmingCharacters(in: .whitespaces)
        if let spaceIndex = trimmed.firstIndex(where: { $0.isWhitespace }) {
            return String(trimmed[..<spaceIndex])
        }
        return trimmed
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sender and timestamp on the same line
            HStack {
                if !message.sender.isEmpty {
                    Button(action: {
                        onCallsignTap(callsignOnly)
                    }) {
                        Text(message.sender)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
                
                Text(message.time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Message text with clickable links
            Text(attributedMessage)
                .font(.body)
                .background(shouldHighlightGreen ? Color.green.opacity(0.3) : (shouldHighlight ? Color.yellow.opacity(0.3) : Color.clear))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Grid info if available
            if !message.grid.getGrid().isEmpty {
                Text("Grid: \(message.grid.getGrid())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}


// MARK: - Preview
struct KSTChatView_Previews: PreviewProvider {
    static var previews: some View {
        KSTChatView()
    }
}

