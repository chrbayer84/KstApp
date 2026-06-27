import Foundation

// MARK: - Backend Service

class BackendService {

    // MARK: - Shared Instance

    static let shared = BackendService()

    // MARK: - Private Properties

    private let baseURL: URL
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    // MARK: - Initialization

    private init() {
        // Get backend URL from UserDefaults or use default
        let backendURLString = UserDefaults.standard.string(forKey: "BackendURL") ?? "https://your-backend.example.com"
        self.baseURL = URL(string: backendURLString)!
    }

    // MARK: - Public Methods

    func updateBackendURL(_ urlString: String) {
        UserDefaults.standard.set(urlString, forKey: "BackendURL")
        // Note: In a production app, you might want to handle URL validation here
    }

    func syncUserSettings(
        username: String,
        password: String,
        gridSquare: String,
        notificationsEnabled: Bool,
        notificationFilter: String,
        deviceToken: String? = nil,
        pushoverUserKey: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Create URL
        let url = baseURL.appendingPathComponent("api/v1/user/\(username)")

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Create request body
        let requestBody = UserSettingsRequest(
            on4kstUsername: username,
            on4kstPassword: password,
            gridSquare: gridSquare.isEmpty ? nil : gridSquare,
            notificationsEnabled: notificationsEnabled,
            notificationFilter: notificationFilter,
            deviceToken: deviceToken,
            pushoverUserKey: pushoverUserKey
        )

        do {
            request.httpBody = try jsonEncoder.encode(requestBody)
        } catch {
            completion(.failure(error))
            return
        }

        // Perform request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            // Check response status
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                let statusCodeError = NSError(
                    domain: "BackendService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"]
                )
                DispatchQueue.main.async {
                    completion(.failure(statusCodeError))
                }
                return
            }

            // Success
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }.resume()
    }

    // MARK: - Private Types

    private struct UserSettingsRequest: Encodable {
        let on4kstUsername: String
        let on4kstPassword: String
        let gridSquare: String?
        let notificationsEnabled: Bool
        let notificationFilter: String
        let deviceToken: String?
        let pushoverUserKey: String?

        enum CodingKeys: String, CodingKey {
            case on4kstUsername
            case on4kstPassword
            case gridSquare
            case notificationsEnabled
            case notificationFilter
            case deviceToken
            case pushoverUserKey
        }
    }
}