import SwiftUI

struct NotionAuthView: View {
    @State private var apiKey: String = ""
    @State private var isValidating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingAPIKey: Bool = false
    @State private var testResultMessage: String? = nil
    @State private var testResultIsError: Bool = false
    @State private var saveTask: Task<Void, Never>? = nil

    private let keychainService = KeychainService.shared

    var body: some View {
        Group {
            Section {
                Group {
                    if showingAPIKey {
                        TextField("Integration token", text: $apiKey)
                    } else {
                        SecureField("Integration token", text: $apiKey)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Toggle("Show API Key", isOn: $showingAPIKey)
            } header: {
                Text("Notion")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste the internal integration token from Notion.")
                    if let url = URL(string: "https://www.notion.so/my-integrations") {
                        Link("Open Notion Integrations", destination: url)
                    }
                }
                .font(.caption)
            }

            Section {
                Button(action: testConnection) {
                    Text(isValidating ? "Testing..." : "Test Connection")
                }
                .disabled(apiKey.isEmpty || isValidating)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Connection")
            } footer: {
                if let message = testResultMessage {
                    Label(message, systemImage: testResultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(testResultIsError ? .red : .green)
                }
            }

        }
        .onAppear {
            loadAPIKey()
        }
        .onChange(of: apiKey) { _, _ in
            testResultMessage = nil
            errorMessage = nil
            scheduleAutoSave()
        }
    }

    private func loadAPIKey() {
        if let savedKey = keychainService.getNotionAPIKey() {
            apiKey = savedKey
        }
    }

    private func scheduleAutoSave() {
        saveTask?.cancel()
        let currentValue = apiKey
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistAPIKey(currentValue)
            }
        }
    }

    private func persistAPIKey(_ value: String) {
        do {
            if value.isEmpty {
                try keychainService.deleteNotionAPIKey()
            } else {
                try keychainService.saveNotionAPIKey(value)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    private func testConnection() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        errorMessage = nil
        testResultMessage = nil

        // First save the API key so NotionClient can use it
        do {
            try keychainService.saveNotionAPIKey(apiKey)
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
            isValidating = false
            testResultMessage = nil
            return
        }

        Task {
            do {
                // Actually test the connection with Notion API
                let success = try await NotionClient.shared.testConnection()

                await MainActor.run {
                    isValidating = false
                    if success {
                        errorMessage = nil
                        testResultMessage = "Connection successful"
                        testResultIsError = false
                    } else {
                        testResultMessage = "Connection test failed"
                        testResultIsError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    testResultMessage = "Connection failed: \(error.localizedDescription)"
                    testResultIsError = true
                    print("[NotionAuthView] Connection test error: \(error)")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            NotionAuthView()
        }
        .formStyle(.grouped)
    }
}
