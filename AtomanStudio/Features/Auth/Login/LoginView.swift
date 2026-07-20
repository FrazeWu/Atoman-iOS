import AtomanCore
import SwiftUI

public struct LoginView: View {
    @Bindable private var viewModel: LoginViewModel

    public init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            TextField("用户名或邮箱", text: $viewModel.username)
            SecureField("密码", text: $viewModel.password)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            Button(viewModel.isLoading ? "登录中…" : "登录") {
                Task { await viewModel.login() }
            }
            .disabled(viewModel.isLoading)
        }
        .navigationTitle("登录")
    }
}
