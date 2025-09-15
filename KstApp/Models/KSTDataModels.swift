import Foundation
import SwiftUI

// MARK: - KST Chat Message
struct KSTChatMsg {
    let time: String
    let sender: String
    let message: String
    let grid: Gridsquare
    
    init(time: String = "", sender: String = "", message: String = "", grid: Gridsquare = Gridsquare()) {
        self.time = time
        self.sender = sender
        self.message = message
        self.grid = grid
    }
}

// MARK: - KST Users Info
struct KSTUsersInfo: Identifiable {
    let id = UUID()
    let callsign: String
    let grid: Gridsquare
    
    init(callsign: String = "", grid: Gridsquare = Gridsquare()) {
        self.callsign = callsign
        self.grid = grid
    }
}

// MARK: - Gridsquare
struct Gridsquare {
    let grid: String
    let isValid: Bool
    let latitude: Double
    let longitude: Double
    
    init(grid: String = "") {
        self.grid = grid
        self.isValid = Gridsquare.isValidGrid(grid)
        (self.latitude, self.longitude) = Gridsquare.coordinatesFromGrid(grid)
    }
    
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.grid = Gridsquare.gridFromCoordinates(latitude: latitude, longitude: longitude)
        self.isValid = true
    }
    
    func getGrid() -> String {
        return grid
    }
    
    func bearingTo(_ other: Gridsquare) -> Double? {
        guard isValid && other.isValid else { return nil }
        return Gridsquare.bearingBetween(lat1: latitude, lon1: longitude, lat2: other.latitude, lon2: other.longitude)
    }
    
    // MARK: - Static Helper Methods
    private static func isValidGrid(_ grid: String) -> Bool {
        let pattern = "^[A-R]{2}[0-9]{2}[A-X]{2}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: grid.utf16.count)
        return regex?.firstMatch(in: grid, options: [], range: range) != nil
    }
    
    private static func coordinatesFromGrid(_ grid: String) -> (Double, Double) {
        guard grid.count == 6 else { return (0, 0) }
        
        let chars = Array(grid.uppercased())
        let field1 = Int(chars[0].asciiValue! - Character("A").asciiValue!)
        let field2 = Int(chars[1].asciiValue! - Character("A").asciiValue!)
        let square1 = Int(String(chars[2])) ?? 0
        let square2 = Int(String(chars[3])) ?? 0
        let subsquare1 = Int(chars[4].asciiValue! - Character("A").asciiValue!)
        let subsquare2 = Int(chars[5].asciiValue! - Character("A").asciiValue!)
        
        let lat = Double(field1 * 10 + square1) + Double(subsquare1) / 24.0 + 1.0/48.0 - 90.0
        let lon = Double(field2 * 20 + square2 * 2) + Double(subsquare2) / 12.0 + 1.0/24.0 - 180.0
        
        return (lat, lon)
    }
    
    private static func gridFromCoordinates(latitude: Double, longitude: Double) -> String {
        let lat = latitude + 90.0
        let lon = longitude + 180.0
        
        let field1 = Int(lat / 10)
        let square1 = Int(lat.truncatingRemainder(dividingBy: 10))
        let subsquare1 = Int((lat.truncatingRemainder(dividingBy: 1)) * 24)
        
        let field2 = Int(lon / 20)
        let square2 = Int((lon.truncatingRemainder(dividingBy: 20)) / 2)
        let subsquare2 = Int(((lon.truncatingRemainder(dividingBy: 20)).truncatingRemainder(dividingBy: 2)) * 12)
        
        let char1 = Character(UnicodeScalar(field1 + Int(Character("A").asciiValue!))!)
        let char2 = Character(UnicodeScalar(field2 + Int(Character("A").asciiValue!))!)
        let char3 = Character(UnicodeScalar(square1 + Int(Character("0").asciiValue!))!)
        let char4 = Character(UnicodeScalar(square2 + Int(Character("0").asciiValue!))!)
        let char5 = Character(UnicodeScalar(subsquare1 + Int(Character("A").asciiValue!))!)
        let char6 = Character(UnicodeScalar(subsquare2 + Int(Character("A").asciiValue!))!)
        
        return String([char1, char2, char3, char4, char5, char6])
    }
    
    private static func bearingBetween(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLon = (lon2 - lon1) * .pi / 180.0
        let lat1Rad = lat1 * .pi / 180.0
        let lat2Rad = lat2 * .pi / 180.0
        
        let y = sin(dLon) * cos(lat2Rad)
        let x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon)
        
        var bearing = atan2(y, x) * 180.0 / .pi
        if bearing < 0 {
            bearing += 360.0
        }
        return bearing
    }
}


// MARK: - Chat Highlight Rule
struct ChatHighlightRule: Identifiable {
    let id = UUID()
    enum InfoSource: Int {
        case sender = 0
        case message = 1
        case gridsquare = 2
    }
    
    enum Operator: Int {
        case contains = 0
        case startsWith = 1
    }
    
    enum InterConditionOperand: Int {
        case and = 0
        case or = 1
    }
    
    struct Condition {
        var source: InfoSource
        var operatorID: Operator
        var value: String
        
        init(source: InfoSource = .sender, operatorID: Operator = .contains, value: String = "") {
            self.source = source
            self.operatorID = operatorID
            self.value = value
        }
    }
    
    let ruleName: String
    let enabled: Bool
    let ruleRoomIndex: Int
    let interConditionOperand: InterConditionOperand
    let conditions: [Condition]
    let ruleValid: Bool
    
    init(ruleName: String = "", enabled: Bool = false, ruleRoomIndex: Int = -1, interConditionOperand: InterConditionOperand = .or, conditions: [Condition] = [], ruleValid: Bool = false) {
        self.ruleName = ruleName
        self.enabled = enabled
        self.ruleRoomIndex = ruleRoomIndex
        self.interConditionOperand = interConditionOperand
        self.conditions = conditions
        self.ruleValid = ruleValid
    }
    
    func match(roomIndex: Int, message: KSTChatMsg) -> Bool {
        guard ruleValid && enabled else { return false }
        guard ruleRoomIndex == 0 || ruleRoomIndex == roomIndex else { return false }
        
        var result = false
        var isFirstCondition = true
        
        for condition in conditions {
            let columnValue: String
            switch condition.source {
            case .sender:
                columnValue = message.sender
            case .message:
                columnValue = message.message
            case .gridsquare:
                columnValue = message.grid.getGrid()
            }
            
            let operatorResult: Bool
            switch condition.operatorID {
            case .contains:
                operatorResult = columnValue.lowercased().contains(condition.value.lowercased())
            case .startsWith:
                operatorResult = columnValue.lowercased().hasPrefix(condition.value.lowercased())
            }
            
            if isFirstCondition {
                result = operatorResult
            } else {
                switch interConditionOperand {
                case .and:
                    result = result && operatorResult
                case .or:
                    result = result || operatorResult
                }
            }
            isFirstCondition = false
        }
        
        return result
    }
}

// MARK: - ChatHighlightRule Codable Extensions
extension ChatHighlightRule: Codable {
    enum CodingKeys: String, CodingKey {
        case ruleName, enabled, ruleRoomIndex, interConditionOperand, conditions, ruleValid
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleName = try container.decode(String.self, forKey: .ruleName)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        ruleRoomIndex = try container.decode(Int.self, forKey: .ruleRoomIndex)
        interConditionOperand = try container.decode(InterConditionOperand.self, forKey: .interConditionOperand)
        conditions = try container.decode([Condition].self, forKey: .conditions)
        ruleValid = try container.decode(Bool.self, forKey: .ruleValid)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ruleName, forKey: .ruleName)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(ruleRoomIndex, forKey: .ruleRoomIndex)
        try container.encode(interConditionOperand, forKey: .interConditionOperand)
        try container.encode(conditions, forKey: .conditions)
        try container.encode(ruleValid, forKey: .ruleValid)
    }
}

extension ChatHighlightRule.Condition: Codable {
    enum CodingKeys: String, CodingKey {
        case source, operatorID, value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(ChatHighlightRule.InfoSource.self, forKey: .source)
        operatorID = try container.decode(ChatHighlightRule.Operator.self, forKey: .operatorID)
        value = try container.decode(String.self, forKey: .value)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(operatorID, forKey: .operatorID)
        try container.encode(value, forKey: .value)
    }
}

extension ChatHighlightRule.InfoSource: Codable {}
extension ChatHighlightRule.Operator: Codable {}
extension ChatHighlightRule.InterConditionOperand: Codable {}

// MARK: - Chat Highlight Evaluator
class ChatHighlightEvaluator: ObservableObject {
    
    // MARK: - Properties
    private var rules: [ChatHighlightRule] = []
    private let roomIndex: Int
    
    // MARK: - Initialization
    init(roomIndex: Int) {
        self.roomIndex = roomIndex
        loadRules()
    }
    
    // MARK: - Public Methods
    func clearRules() {
        rules.removeAll()
    }
    
    func loadRules() {
        clearRules()
        
        // In a real implementation, this would load from Core Data or UserDefaults
        // For now, we'll create some example rules
        let exampleRules = [
            ChatHighlightRule(
                ruleName: "My Callsign",
                enabled: true,
                ruleRoomIndex: roomIndex,
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .sender,
                        operatorID: .contains,
                        value: "MYCALL"
                    )
                ],
                ruleValid: true
            ),
            ChatHighlightRule(
                ruleName: "Emergency",
                enabled: true,
                ruleRoomIndex: 0, // All rooms
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .message,
                        operatorID: .contains,
                        value: "EMERGENCY"
                    ),
                    ChatHighlightRule.Condition(
                        source: .message,
                        operatorID: .contains,
                        value: "HELP"
                    )
                ],
                ruleValid: true
            ),
            ChatHighlightRule(
                ruleName: "Local Grid",
                enabled: true,
                ruleRoomIndex: roomIndex,
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .gridsquare,
                        operatorID: .startsWith,
                        value: "JN"
                    )
                ],
                ruleValid: true
            )
        ]
        
        rules = exampleRules
    }
    
    func shouldHighlight(_ message: KSTChatMsg) -> (shouldHighlight: Bool, matchedRules: [String]) {
        var matchedRules: [String] = []
        
        for rule in rules {
            if rule.match(roomIndex: roomIndex, message: message) {
                matchedRules.append(rule.ruleName)
            }
        }
        
        return (matchedRules.count > 0, matchedRules)
    }
    
    func addRule(_ rule: ChatHighlightRule) {
        rules.append(rule)
        saveRules()
    }
    
    func removeRule(named ruleName: String) {
        rules.removeAll { $0.ruleName == ruleName }
        saveRules()
    }
    
    func updateRule(_ rule: ChatHighlightRule) {
        if let index = rules.firstIndex(where: { $0.ruleName == rule.ruleName }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    func getAllRules() -> [ChatHighlightRule] {
        return rules
    }
    
    func updateMyCallsignRule(callsign: String) {
        let callsignUpper = callsign.uppercased()
        
        // Find the "My Callsign" rule
        if let index = rules.firstIndex(where: { $0.ruleName == "My Callsign" }) {
            // Update the existing rule by creating a new one with updated conditions
            let existingRule = rules[index]
            var updatedConditions = existingRule.conditions
            if let conditionIndex = updatedConditions.firstIndex(where: { $0.source == .sender }) {
                updatedConditions[conditionIndex] = ChatHighlightRule.Condition(
                    source: .sender,
                    operatorID: updatedConditions[conditionIndex].operatorID,
                    value: callsignUpper
                )
                let updatedRule = ChatHighlightRule(
                    ruleName: existingRule.ruleName,
                    enabled: existingRule.enabled,
                    ruleRoomIndex: existingRule.ruleRoomIndex,
                    interConditionOperand: existingRule.interConditionOperand,
                    conditions: updatedConditions,
                    ruleValid: existingRule.ruleValid
                )
                rules[index] = updatedRule
                saveRules()
            }
        } else {
            // Create a new "My Callsign" rule if it doesn't exist
            let newRule = ChatHighlightRule(
                ruleName: "My Callsign",
                enabled: true,
                ruleRoomIndex: 0, // All rooms
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .sender,
                        operatorID: .contains,
                        value: callsignUpper
                    )
                ],
                ruleValid: true
            )
            rules.append(newRule)
            saveRules()
        }
    }
    
    // MARK: - Private Methods
    private func saveRules() {
        // In a real implementation, this would save to Core Data or UserDefaults
        // For now, we'll just keep them in memory
    }
}

// MARK: - Chat Highlight Rule Manager
class ChatHighlightRuleManager: ObservableObject {
    
    // MARK: - Properties
    @Published var rules: [ChatHighlightRule] = []
    
    // MARK: - Initialization
    init() {
        loadRules()
    }
    
    // MARK: - Public Methods
    func addRule(_ rule: ChatHighlightRule) {
        rules.append(rule)
        saveRules()
    }
    
    func removeRule(named ruleName: String) {
        rules.removeAll { $0.ruleName == ruleName }
        saveRules()
    }
    
    func updateRule(_ rule: ChatHighlightRule) {
        if let index = rules.firstIndex(where: { $0.ruleName == rule.ruleName }) {
            rules[index] = rule
            saveRules()
        }
    }
    
    func getRulesForRoom(_ roomIndex: Int) -> [ChatHighlightRule] {
        return rules.filter { $0.ruleRoomIndex == roomIndex || $0.ruleRoomIndex == 0 }
    }
    
    func getAllRuleNames() -> [String] {
        return rules.map { $0.ruleName }.sorted()
    }
    
    // MARK: - Private Methods
    private func loadRules() {
        // Load from UserDefaults for now
        if let data = UserDefaults.standard.data(forKey: "ChatHighlightRules"),
           let decodedRules = try? JSONDecoder().decode([ChatHighlightRule].self, from: data) {
            rules = decodedRules
        } else {
            // Create default rules
            createDefaultRules()
        }
    }
    
    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: "ChatHighlightRules")
        }
    }
    
    private func createDefaultRules() {
        // Get the callsign from UserDefaults or use default
        let callsign = UserDefaults.standard.string(forKey: "KSTUsername")?.uppercased() ?? "MYCALL"
        
        let defaultRules = [
            ChatHighlightRule(
                ruleName: "My Callsign",
                enabled: true,
                ruleRoomIndex: 0, // All rooms
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .sender,
                        operatorID: .contains,
                        value: callsign
                    )
                ],
                ruleValid: true
            ),
            ChatHighlightRule(
                ruleName: "Emergency",
                enabled: true,
                ruleRoomIndex: 0, // All rooms
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .message,
                        operatorID: .contains,
                        value: "EMERGENCY"
                    ),
                    ChatHighlightRule.Condition(
                        source: .message,
                        operatorID: .contains,
                        value: "HELP"
                    )
                ],
                ruleValid: true
            )
        ]
        
        rules = defaultRules
        saveRules()
    }
    
    func updateMyCallsignRule(callsign: String) {
        let callsignUpper = callsign.uppercased()
        
        // Find the "My Callsign" rule
        if let index = rules.firstIndex(where: { $0.ruleName == "My Callsign" }) {
            // Update the existing rule by creating a new one with updated conditions
            let existingRule = rules[index]
            var updatedConditions = existingRule.conditions
            if let conditionIndex = updatedConditions.firstIndex(where: { $0.source == .sender }) {
                updatedConditions[conditionIndex] = ChatHighlightRule.Condition(
                    source: .sender,
                    operatorID: updatedConditions[conditionIndex].operatorID,
                    value: callsignUpper
                )
                let updatedRule = ChatHighlightRule(
                    ruleName: existingRule.ruleName,
                    enabled: existingRule.enabled,
                    ruleRoomIndex: existingRule.ruleRoomIndex,
                    interConditionOperand: existingRule.interConditionOperand,
                    conditions: updatedConditions,
                    ruleValid: existingRule.ruleValid
                )
                rules[index] = updatedRule
                saveRules()
            }
        } else {
            // Create a new "My Callsign" rule if it doesn't exist
            let newRule = ChatHighlightRule(
                ruleName: "My Callsign",
                enabled: true,
                ruleRoomIndex: 0, // All rooms
                interConditionOperand: .or,
                conditions: [
                    ChatHighlightRule.Condition(
                        source: .sender,
                        operatorID: .contains,
                        value: callsignUpper
                    )
                ],
                ruleValid: true
            )
            rules.append(newRule)
            saveRules()
        }
    }
}

