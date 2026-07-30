import Foundation

protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TodoistClientError.invalidResponse
        }
        return (data, response)
    }
}

protocol TodoistConnecting {
    func testConnection(token: String) async throws -> TodoistUser
}

protocol TodoistSyncing {
    func syncResources(
        token: String,
        syncToken: String
    ) async throws -> TodoistSyncResponse
}

struct TodoistUser: Decodable, Equatable {
    let id: String
    let fullName: String
    let email: String?

    init(id: String, fullName: String, email: String? = nil) {
        self.id = id
        self.fullName = fullName
        self.email = email
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? values.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try values.decode(Int64.self, forKey: .id))
        }
        fullName = try values.decode(String.self, forKey: .fullName)
        email = try values.decodeIfPresent(String.self, forKey: .email)
    }
}

enum TodoistClientError: LocalizedError, Equatable {
    case emptyToken
    case badRequest
    case unauthorized
    case forbidden
    case rateLimited(retryAfterSeconds: Int?)
    case server(statusCode: Int)
    case invalidResponse
    case network

    var errorDescription: String? {
        switch self {
        case .emptyToken:
            return NSLocalizedString(
                "TodoistClientError.emptyToken",
                comment: "Empty Todoist token error"
            )
        case .badRequest:
            return NSLocalizedString(
                "TodoistClientError.badRequest",
                comment: "Invalid Todoist request error"
            )
        case .unauthorized:
            return NSLocalizedString(
                "TodoistClientError.unauthorized",
                comment: "Invalid Todoist token error"
            )
        case .forbidden:
            return NSLocalizedString(
                "TodoistClientError.forbidden",
                comment: "Todoist permission error"
            )
        case let .rateLimited(retryAfterSeconds):
            if let retryAfterSeconds {
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "TodoistClientError.rateLimitedWithDelay",
                        comment: "Todoist rate limit error with retry delay"
                    ),
                    retryAfterSeconds
                )
            }
            return NSLocalizedString(
                "TodoistClientError.rateLimited",
                comment: "Todoist rate limit error"
            )
        case .server:
            return NSLocalizedString(
                "TodoistClientError.server",
                comment: "Todoist server error"
            )
        case .invalidResponse:
            return NSLocalizedString(
                "TodoistClientError.invalidResponse",
                comment: "Invalid Todoist response error"
            )
        case .network:
            return NSLocalizedString(
                "TodoistClientError.network",
                comment: "Todoist network error"
            )
        }
    }
}

struct TodoistClient: TodoistConnecting, TodoistSyncing {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://api.todoist.com/api/v1")!,
        transport: HTTPTransport = URLSessionHTTPTransport(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = decoder
    }

    func testConnection(token: String) async throws -> TodoistUser {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw TodoistClientError.emptyToken
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("user"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data = try await perform(request)
        do {
            return try decoder.decode(TodoistUser.self, from: data)
        } catch {
            throw TodoistClientError.invalidResponse
        }
    }

    func syncResources(
        token: String,
        syncToken: String
    ) async throws -> TodoistSyncResponse {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw TodoistClientError.emptyToken
        }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "sync_token", value: syncToken),
            URLQueryItem(
                name: "resource_types",
                value: #"["projects","items"]"#
            ),
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data = try await perform(request)
        do {
            return try decoder.decode(TodoistSyncResponse.self, from: data)
        } catch {
            throw TodoistClientError.invalidResponse
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as TodoistClientError {
            throw error
        } catch {
            throw TodoistClientError.network
        }

        switch response.statusCode {
        case 200 ..< 300:
            return data
        case 400:
            throw TodoistClientError.badRequest
        case 401:
            throw TodoistClientError.unauthorized
        case 403:
            throw TodoistClientError.forbidden
        case 429:
            throw TodoistClientError.rateLimited(
                retryAfterSeconds: response.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Int.init)
            )
        case 500 ..< 600:
            throw TodoistClientError.server(statusCode: response.statusCode)
        default:
            throw TodoistClientError.invalidResponse
        }
    }
}
