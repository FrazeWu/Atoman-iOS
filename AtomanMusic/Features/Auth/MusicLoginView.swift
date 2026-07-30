import AtomanCore
import SwiftUI

struct MusicLoginView: View {
    @State private var viewModel: LoginViewModel
    @State private var showsPassword = false
    let registrationURL: URL
    let passwordResetURL: URL
    let onLogin: () async -> Void

    init(
        client: APIClient,
        authSession: AuthSessionStore,
        registrationURL: URL,
        passwordResetURL: URL,
        onLogin: @escaping () async -> Void
    ) {
        self._viewModel = State(initialValue: LoginViewModel(client: client, authSession: authSession))
        self.registrationURL = registrationURL
        self.passwordResetURL = passwordResetURL
        self.onLogin = onLogin
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.musicAccent)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("用户名或邮箱")
                            .font(.subheadline.weight(.semibold))
                        TextField("输入用户名或邮箱", text: $viewModel.username)
                            .textContentType(.username)
                            .submitLabel(.next)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(loginFieldBackground)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("密码")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 0) {
                            Group {
                                if showsPassword {
                                    TextField("输入密码", text: $viewModel.password)
                                } else {
                                    SecureField("输入密码", text: $viewModel.password)
                                }
                            }
                            .textContentType(.password)
                            .onSubmit { login() }

                            Button {
                                showsPassword.toggle()
                            } label: {
                                Image(systemName: showsPassword ? "eye.slash" : "eye")
                                    .font(.system(size: 18, weight: .medium))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(showsPassword ? "隐藏密码" : "显示密码")
                        }
                        .padding(.leading, 12)
                        .frame(minHeight: 44)
                        .background(loginFieldBackground)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: login) {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("登录").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSubmit)

                HStack(spacing: 24) {
                    Link("注册账号", destination: registrationURL)
                    Link("忘记密码", destination: passwordResetURL)
                }
                .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: 420)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func login() {
        guard viewModel.canSubmit else { return }
        Task {
            if await viewModel.login() {
                await onLogin()
            }
        }
    }

    private var loginFieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.musicSurface)
            .stroke(.white.opacity(0.12), lineWidth: 1)
    }
}
