import AtomanCore
import SwiftUI

public struct AuthenticationGateView<Content: View>: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isLoginPresented = false

    private let title: String
    private let message: String
    private let content: () -> Content

    public init(
        title: String,
        message: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.content = content
    }

    public var body: some View {
        switch AuthenticationGateState.resolve(session: environment.authSession) {
        case .authenticated:
            content()
        case .requiresLogin:
            VStack(spacing: 16) {
                Image(systemName: "lock.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("登录") {
                    isLoginPresented = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle(title)
            .sheet(isPresented: $isLoginPresented) {
                NavigationStack {
                    LoginView(
                        viewModel: LoginViewModel(
                            client: environment.apiClient,
                            authSession: environment.authSession
                        )
                    )
                }
            }
        }
    }
}
