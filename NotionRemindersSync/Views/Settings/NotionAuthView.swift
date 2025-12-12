import SwiftUI

struct NotionAuthView: View {
    @State private var apiKey: String = ""
    @State private var isValidating: Bool = false
    @State private var isConnected: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingAPIKey: Bool = false

    private let keychainService = KeychainService.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if showingAPIKey {
                            TextField("Enter Notion API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("Enter Notion API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showingAPIKey.toggle() }) {
                            Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    Text("Get your API key from [Notion Integrations](https://www.notion.so/my-integrations)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("API Key")
            }

            Section {
                HStack {
                    connectionStatusView

                    Spacer()

                    Button(action: testConnection) {
                        HStack(spacing: 4) {
                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text(isValidating ? "Testing..." : "Test Connection")
                        }
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Connection Status")
            }

            Section {
                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty)

                    if isConnected {
                        Button("Remove API Key", role: .destructive) {
                            removeAPIKey()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notion")
        .padding()
        .onAppear {
            loadAPIKey()
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Not Connected")
                .font(.subheadline)
                .foregroundColor(isConnected ? .green : .secondary)
        }
    }

    private func loadAPIKey() {
        if let savedKey = keychainService.getNotionAPIKey() {
            apiKey = savedKey
            isConnected = true
        }
    }

    private func saveAPIKey() {
        do {
            try keychainService.saveNotionAPIKey(apiKey)
            isConnected = true
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    private func removeAPIKey() {
        do {
            try keychainService.deleteNotionAPIKey()
            apiKey = ""
            isConnected = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to remove API key: \(error.localizedDescription)"
        }
    }

    private func testConnection() {
        guard !apiKey.isEmpty else { return }

        isValidating = true
        errorMessage = nil

        // First save the API key so NotionClient can use it
        do {
            try keychainService.saveNotionAPIKey(apiKey)
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
            isValidating = false
            return
        }

        Task {
            do {
                // Actually test the connection with Notion API
                let success = try await NotionClient.shared.testConnection()

                await MainActor.run {
                    isValidating = false
                    if success {
                        isConnected = true
                        errorMessage = nil
                    } else {
                        isConnected = false
                        errorMessage = "Connection test failed"
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    isConnected = false
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                    print("[NotionAuthView] Connection test error: \(error)")
                }
            }
        }
    }
}

#Preview {
    NotionAuthView()
}
