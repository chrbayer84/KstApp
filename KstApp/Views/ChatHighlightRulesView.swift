import SwiftUI
import SafariServices

struct ChatHighlightRulesView: View {
    @StateObject private var ruleManager = ChatHighlightRuleManager()
    @StateObject private var chatManager = KSTChatManager.shared
    @State private var showingAddRule = false
    @State private var editingRule: ChatHighlightRule?
    @State private var showingPrivacyPolicy = false
    @AppStorage("KSTBackendURL") private var storedBackendURL: String = ""

    private let privacyPolicyURL = URL(string: "https://chrbayer84.github.io/KstApp/PRIVACY.html")!

    private var backendStatusText: String {
        guard !storedBackendURL.isEmpty,
              storedBackendURL != "https://your-backend.example.com" else {
            return "Not configured"
        }
        return URL(string: storedBackendURL)?.host ?? storedBackendURL
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Enable Notifications", isOn: $chatManager.notificationsEnabled)

                    Picker("Notification Filter", selection: $chatManager.notificationFilter) {
                        ForEach(KSTChatManager.NotificationFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                } header: {
                    Text("Push Notifications")
                } footer: {
                    Text("Requires a configured backend. Leave the Pushover key empty to use APNs.")
                }

                Section("Notification Delivery") {
                    NavigationLink {
                        BackendConfigurationView()
                    } label: {
                        HStack {
                            Text("Backend Configuration")
                            Spacer()
                            Text(backendStatusText)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Section {
                    ForEach(ruleManager.rules, id: \.ruleName) { rule in
                        RuleRow(rule: rule) {
                            editingRule = rule
                        }
                    }
                    .onDelete(perform: deleteRules)

                    Button {
                        showingAddRule = true
                    } label: {
                        Label("Add Rule", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Highlight Rules")
                }

                Section("About") {
                    Button {
                        showingPrivacyPolicy = true
                    } label: {
                        HStack {
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddRule) {
                RuleEditView(rule: nil) { newRule in
                    ruleManager.addRule(newRule)
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditView(rule: rule) { updatedRule in
                    ruleManager.updateRule(updatedRule)
                }
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                SafariView(url: privacyPolicyURL)
                    .ignoresSafeArea()
            }
        }
    }

    private func deleteRules(offsets: IndexSet) {
        for index in offsets {
            let rule = ruleManager.rules[index]
            ruleManager.removeRule(named: rule.ruleName)
        }
    }
}

// MARK: - Backend Configuration View
struct BackendConfigurationView: View {
    private enum Field: Hashable {
        case backendURL
        case pushoverKey
    }

    private enum TestStatus {
        case testing
        case success
        case failure(String)
    }

    @State private var backendURL: String
    @State private var pushoverUserKey: String
    @State private var testStatus: TestStatus?
    @FocusState private var focusedField: Field?

    private static let placeholderBackendURL = "https://your-backend.example.com"

    init() {
        let storedBackendURL = UserDefaults.standard.string(forKey: "KSTBackendURL") ?? ""
        let initialBackendURL = storedBackendURL == Self.placeholderBackendURL ? "" : storedBackendURL
        _backendURL = State(initialValue: initialBackendURL)
        _pushoverUserKey = State(initialValue: UserDefaults.standard.string(forKey: "KSTPushoverUserKey") ?? "")
    }

    private var trimmedBackendURL: String {
        backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isBackendURLValid: Bool {
        Self.isValidBackendURL(trimmedBackendURL)
    }

    private var isTesting: Bool {
        if case .testing? = testStatus {
            return true
        }
        return false
    }

    var body: some View {
        Form {
            Section {
                TextField("https://your-backend.example.com", text: $backendURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .backendURL)

                SecureField("Pushover User Key", text: $pushoverUserKey)
                    .focused($focusedField, equals: .pushoverKey)
            } header: {
                Text("Backend")
            } footer: {
                if !trimmedBackendURL.isEmpty && !isBackendURLValid {
                    Text("Enter a valid http:// or https:// URL.")
                        .foregroundColor(.red)
                } else {
                    Text("Leave the backend URL empty if you do not use a push relay. The Pushover key is optional; leave it blank to use APNs.")
                }
            }

            Section("Test") {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(trimmedBackendURL.isEmpty || !isBackendURLValid || isTesting)

                if let testStatus {
                    statusView(testStatus)
                }
            }

            Section {
                Text("Settings are saved automatically and synced with the backend after you leave this screen.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Backend Configuration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onChange(of: backendURL) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || Self.isValidBackendURL(trimmed) {
                UserDefaults.standard.set(trimmed, forKey: "KSTBackendURL")
            }
            testStatus = nil
        }
        .onChange(of: pushoverUserKey) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "KSTPushoverUserKey")
        }
        .onDisappear {
            if trimmedBackendURL.isEmpty || isBackendURLValid {
                UserDefaults.standard.set(trimmedBackendURL, forKey: "KSTBackendURL")
            }
            KSTChatManager.shared.syncSettingsWithBackend()
        }
    }

    private static func isValidBackendURL(_ value: String) -> Bool {
        guard !value.isEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = url.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    private func testConnection() {
        guard let url = URL(string: trimmedBackendURL)?.appendingPathComponent("health") else {
            return
        }

        testStatus = .testing
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    testStatus = .failure(error.localizedDescription)
                } else if let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) {
                    testStatus = .success
                } else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    testStatus = .failure("HTTP \(statusCode)")
                }
            }
        }.resume()
    }

    @ViewBuilder
    private func statusView(_ status: TestStatus) -> some View {
        switch status {
        case .testing:
            Text("Testing...")
                .foregroundColor(.secondary)
        case .success:
            Label("Backend reachable", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundColor(.red)
        }
    }
}

// MARK: - Rule Row
struct RuleRow: View {
    let rule: ChatHighlightRule
    let onEdit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.ruleName)
                    .font(.headline)
                
                Spacer()
                
                if rule.enabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
            
            Text(roomDescription(for: rule.ruleRoomIndex))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(conditionsDescription(for: rule.conditions))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
    
    private func roomDescription(for roomIndex: Int) -> String {
        if roomIndex == 0 {
            return "All Rooms"
        } else if roomIndex <= KSTChatManager.chatRooms.count {
            return KSTChatManager.chatRooms[roomIndex - 1]
        } else {
            return "Unknown Room"
        }
    }
    
    private func conditionsDescription(for conditions: [ChatHighlightRule.Condition]) -> String {
        return conditions.map { condition in
            let source = sourceDescription(condition.source)
            let operatorDesc = operatorDescription(condition.operatorID)
            return "\(source) \(operatorDesc) '\(condition.value)'"
        }.joined(separator: " \(rule.interConditionOperand == .and ? "AND" : "OR") ")
    }
    
    private func sourceDescription(_ source: ChatHighlightRule.InfoSource) -> String {
        switch source {
        case .sender: return "Sender"
        case .message: return "Message"
        case .gridsquare: return "Grid"
        }
    }
    
    private func operatorDescription(_ operatorID: ChatHighlightRule.Operator) -> String {
        switch operatorID {
        case .contains: return "contains"
        case .startsWith: return "starts with"
        }
    }
}

// MARK: - Rule Edit View
struct RuleEditView: View {
    let rule: ChatHighlightRule?
    let onSave: (ChatHighlightRule) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var ruleName = ""
    @State private var enabled = true
    @State private var roomIndex = 0
    @State private var interConditionOperand = ChatHighlightRule.InterConditionOperand.or
    @State private var conditions: [ChatHighlightRule.Condition] = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Rule Details") {
                    TextField("Rule Name", text: $ruleName)
                    
                    Toggle("Enabled", isOn: $enabled)
                    
                    Picker("Room", selection: $roomIndex) {
                        Text("All Rooms").tag(0)
                        ForEach(1...KSTChatManager.chatRooms.count, id: \.self) { index in
                            Text(KSTChatManager.chatRooms[index - 1]).tag(index)
                        }
                    }
                }
                
                Section("Conditions") {
                    Picker("Combine with", selection: $interConditionOperand) {
                        Text("OR").tag(ChatHighlightRule.InterConditionOperand.or)
                        Text("AND").tag(ChatHighlightRule.InterConditionOperand.and)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    ForEach(Array(conditions.enumerated()), id: \.offset) { index, condition in
                        ConditionRow(
                            condition: $conditions[index],
                            onDelete: {
                                conditions.remove(at: index)
                            }
                        )
                    }
                    
                    Button("Add Condition") {
                        conditions.append(ChatHighlightRule.Condition())
                    }
                }
            }
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveRule()
                    }
                    .disabled(ruleName.isEmpty || conditions.isEmpty)
                }
            }
        }
        .onAppear {
            if let rule = rule {
                ruleName = rule.ruleName
                enabled = rule.enabled
                roomIndex = rule.ruleRoomIndex
                interConditionOperand = rule.interConditionOperand
                conditions = rule.conditions
            } else {
                conditions = [ChatHighlightRule.Condition()]
            }
        }
    }
    
    private func saveRule() {
        let newRule = ChatHighlightRule(
            ruleName: ruleName,
            enabled: enabled,
            ruleRoomIndex: roomIndex,
            interConditionOperand: interConditionOperand,
            conditions: conditions,
            ruleValid: true
        )
        
        onSave(newRule)
        dismiss()
    }
}

// MARK: - Condition Row
struct ConditionRow: View {
    @Binding var condition: ChatHighlightRule.Condition
    let onDelete: () -> Void
    @StateObject private var chatManager = KSTChatManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Condition")
                    .font(.headline)
                
                Spacer()
                
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                .font(.caption)
            }
            
            Picker("Source", selection: $condition.source) {
                Text("Sender").tag(ChatHighlightRule.InfoSource.sender)
                Text("Message").tag(ChatHighlightRule.InfoSource.message)
                Text("Grid").tag(ChatHighlightRule.InfoSource.gridsquare)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            Picker("Operator", selection: $condition.operatorID) {
                Text("Contains").tag(ChatHighlightRule.Operator.contains)
                Text("Starts With").tag(ChatHighlightRule.Operator.startsWith)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            if condition.source == .sender && !chatManager.myCallsign.isEmpty && 
               (condition.value.uppercased() == chatManager.myCallsign.uppercased() || 
                condition.value.uppercased() == "MYCALL") {
                HStack {
                    Text("Value:")
                    Text(chatManager.myCallsign.isEmpty ? "Not logged in" : chatManager.myCallsign)
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("(Auto-filled from login)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            } else {
                TextField("Value", text: $condition.value)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Safari View
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = .systemBlue
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Preview
struct ChatHighlightRulesView_Previews: PreviewProvider {
    static var previews: some View {
        ChatHighlightRulesView()
    }
}

