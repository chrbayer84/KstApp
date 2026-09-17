import XCTest

class KSTChatManagerRegexTests: XCTestCase {

    func testUserListRegex() {
        let pattern = "^\\(?(\\S+?)\\)?\\s+\\(?([A-Ra-r]{2}[0-9]{2}[A-Xa-x]{0,2})\\)?(?:\\s+(.*))?$"
        let regex = try! NSRegularExpression(pattern: pattern)
        
        let cases = [
            (
                line: "VA3IKE        (EN92xx)    Ike",
                expectedCallsign: "VA3IKE",
                expectedGrid: "EN92xx",
                expectedName: "Ike"
            ),
            (
                line: "(VA3IKE)      (EN92xx)    Ike",
                expectedCallsign: "VA3IKE",
                expectedGrid: "EN92xx",
                expectedName: "Ike"
            ),
            (
                line: "VA3IKE        (EN92)      Ike",
                expectedCallsign: "VA3IKE",
                expectedGrid: "EN92",
                expectedName: "Ike"
            ),
            (
                line: "VA3IKE        EN92xx      Ike",
                expectedCallsign: "VA3IKE",
                expectedGrid: "EN92xx",
                expectedName: "Ike"
            ),
            (
                line: "ON1ABC/M      (JO20ab)    Marc Mobile",
                expectedCallsign: "ON1ABC/M",
                expectedGrid: "JO20ab",
                expectedName: "Marc Mobile"
            ),
            (
                line: "PA3XYZ        (JO21)",
                expectedCallsign: "PA3XYZ",
                expectedGrid: "JO21",
                expectedName: ""
            ),
            (
                line: "F5DEF         JN18        Pierre",
                expectedCallsign: "F5DEF",
                expectedGrid: "JN18",
                expectedName: "Pierre"
            )
        ]
        
        for c in cases {
            let match = regex.firstMatch(in: c.line, range: NSRange(c.line.startIndex..., in: c.line))
            XCTAssertNotNil(match, "Failed to match line: \(c.line)")
            
            if let match = match {
                let callsign = String(c.line[Range(match.range(at: 1), in: c.line)!]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
                XCTAssertEqual(callsign, c.expectedCallsign)
                
                let grid = String(c.line[Range(match.range(at: 2), in: c.line)!]).replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
                XCTAssertEqual(grid, c.expectedGrid)
                
                var name = ""
                if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound {
                    name = String(c.line[Range(match.range(at: 3), in: c.line)!]).trimmingCharacters(in: .whitespaces)
                }
                XCTAssertEqual(name, c.expectedName)
            }
        }
    }
    
    func testChatMessageRegex() {
        let pattern = "([0-9]{4})Z ([^>]+)>(.*)"
        let regex = try! NSRegularExpression(pattern: pattern)
        
        let cases = [
            (
                line: "1205Z VA3IKE Ike (EN92xx)>Hello everyone",
                expectedTime: "1205",
                expectedSender: "VA3IKE Ike (EN92xx)",
                expectedMessage: "Hello everyone"
            ),
            (
                line: "0001Z ON1ABC>This is a > test message > with brackets",
                expectedTime: "0001",
                expectedSender: "ON1ABC",
                expectedMessage: "This is a > test message > with brackets"
            )
        ]
        
        for c in cases {
            let match = regex.firstMatch(in: c.line, range: NSRange(c.line.startIndex..., in: c.line))
            XCTAssertNotNil(match, "Failed to match line: \(c.line)")
            
            if let match = match {
                let time = String(c.line[Range(match.range(at: 1), in: line)!])
                XCTAssertEqual(time, c.expectedTime)
                
                let sender = String(c.line[Range(match.range(at: 2), in: line)!])
                XCTAssertEqual(sender, c.expectedSender)
                
                let message = String(c.line[Range(match.range(at: 3), in: line)!])
                XCTAssertEqual(message, c.expectedMessage)
            }
        }
    }
}
