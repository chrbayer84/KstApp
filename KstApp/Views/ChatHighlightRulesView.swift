import SwiftUI

struct ChatHighlightRulesView: View {
    @StateObject private var ruleManager = ChatHighlightRuleManager()
    @StateObject private var chatManager = KSTChatManager()
    @State private var showingAddRule = false
    @State private var editingRule: ChatHighlightRule?
    
    var body: some View {
        NavigationStack {
            List {
                // Push Notification Settings Section
                Section("Push Notifications") {
                    Toggle("Enable Notifications", isOn: $chatManager.notificationsEnabled)
                    
                    Picker("Notification Filter", selection: $chatManager.notificationFilter) {
                        ForEach(KSTChatManager.NotificationFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // Highlight Rules Section
                Section("Highlight Rules") {
                    ForEach(ruleManager.rules, id: \.ruleName) { rule in
                        RuleRow(rule: rule) {
                            editingRule = rule
                        }
                    }
                    .onDelete(perform: deleteRules)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showingAddRule = true
                    }
                }
            }
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
        }
    }
    
    private func deleteRules(offsets: IndexSet) {
        for index in offsets {
            let rule = ruleManager.rules[index]
            ruleManager.removeRule(named: rule.ruleName)
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
    @StateObject private var chatManager = KSTChatManager()
    
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

// MARK: - Preview
struct ChatHighlightRulesView_Previews: PreviewProvider {
    static var previews: some View {
        ChatHighlightRulesView()
    }
}

