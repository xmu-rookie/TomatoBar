import SwiftUI

struct TodoistSettingsView: View {
    @ObservedObject var viewModel: TodoistConnectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusView

            if !viewModel.hasStoredToken {
                SecureField(
                    NSLocalizedString(
                        "TodoistSettings.token.placeholder",
                        comment: "Todoist API token placeholder"
                    ),
                    text: $viewModel.tokenInput
                )
                .textFieldStyle(.roundedBorder)

                Button {
                    Task {
                        await viewModel.connect()
                    }
                } label: {
                    Text(NSLocalizedString(
                        "TodoistSettings.connect.label",
                        comment: "Connect Todoist button"
                    ))
                    .frame(maxWidth: .infinity)
                }
                .disabled(!viewModel.canConnect)
            } else {
                HStack {
                    Button {
                        Task {
                            await viewModel.testSavedConnection()
                        }
                    } label: {
                        Text(NSLocalizedString(
                            "TodoistSettings.testAgain.label",
                            comment: "Test Todoist connection again button"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.state == .testing)

                    Button(role: .destructive) {
                        viewModel.disconnect()
                    } label: {
                        Text(NSLocalizedString(
                            "TodoistSettings.disconnect.label",
                            comment: "Disconnect Todoist button"
                        ))
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Text(NSLocalizedString(
                "TodoistSettings.security.help",
                comment: "Todoist token security explanation"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(minHeight: 0)
        }
        .padding(4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.state {
        case .disconnected:
            Label(
                NSLocalizedString(
                    "TodoistSettings.disconnected.status",
                    comment: "Todoist disconnected status"
                ),
                systemImage: "link.badge.plus"
            )
        case .testing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(NSLocalizedString(
                    "TodoistSettings.testing.status",
                    comment: "Todoist connection testing status"
                ))
            }
        case let .connected(displayName):
            Label(
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "TodoistSettings.connected.status",
                        comment: "Connected Todoist account status"
                    ),
                    displayName
                ),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
