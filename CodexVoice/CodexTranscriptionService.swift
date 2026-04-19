import AppKit
import Darwin
import Foundation

enum CodexTranscriptionError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Codex returned an invalid transcription response."
        case .unauthorized:
            return "Codex auth expired. Open Codex and sign in again."
        case .serverError(let message):
            return "Codex transcription failed: \(message)"
        }
    }
}

actor CodexTranscriptionService {
    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private let authService: CodexAuthService
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/transcribe")!

    init(authService: CodexAuthService) {
        self.authService = authService
    }

    func transcribe(_ recording: RecordedAudio) async throws -> String {
        DebugLogger.write("Transcription start: \(recording.filename)")
        let initialCredentials = try await authService.currentCredentials()

        do {
            let transcript = try await performTranscription(recording, credentials: initialCredentials)
            DebugLogger.write("Transcription success: chars=\(transcript.count)")
            return transcript
        } catch CodexTranscriptionError.unauthorized {
            DebugLogger.write("Transcription unauthorized, refreshing auth")
            let refreshedCredentials = try await authService.refreshCredentials()
            let transcript = try await performTranscription(recording, credentials: refreshedCredentials)
            DebugLogger.write("Transcription success after refresh: chars=\(transcript.count)")
            return transcript
        } catch {
            DebugLogger.write("Transcription failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func performTranscription(_ recording: RecordedAudio, credentials: CodexCredentials) async throws -> String {
        let boundary = "----codex-voice-\(UUID().uuidString)"
        let body = try makeMultipartBody(recording: recording, boundary: boundary)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue(codexDesktopUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexTranscriptionError.invalidResponse
        }
        DebugLogger.write("Transcription HTTP status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            throw CodexTranscriptionError.unauthorized
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexTranscriptionError.serverError(message?.isEmpty == false ? message! : "HTTP \(httpResponse.statusCode)")
        }

        if let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
            return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw CodexTranscriptionError.invalidResponse
    }

    private func makeMultipartBody(recording: RecordedAudio, boundary: String) throws -> Data {
        var body = Data()
        let fileData = try Data(contentsOf: recording.url)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(recording.filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(recording.contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

    private func codexDesktopUserAgent() -> String {
        let codexBundleURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let codexBundle = Bundle(url: codexBundleURL)
        let version = codexBundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        let arch = ProcessInfo.processInfo.machineHardwareName ?? "arm64"
        return "Codex Desktop/\(version) (Mac OS \(osString); \(arch))"
    }
}

private extension ProcessInfo {
    var machineHardwareName: String? {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
