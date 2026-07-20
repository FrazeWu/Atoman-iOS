import AtomanCore
import SwiftUI

struct MusicAccountButton: View {
    @Environment(MusicAppEnvironment.self) private var environment

    var body: some View {
        Button {
            environment.authentication.present()
        } label: {
            MusicAccountAvatar(user: environment.authSession.user, size: 32)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(environment.authSession.isAuthenticated ? "账号" : "登录")
    }
}

struct MusicAccountSheet: View {
    @Environment(MusicAppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            Group {
                if environment.authSession.isAuthenticated {
                    authenticatedContent
                } else {
                    MusicLoginView(
                        client: environment.api.client,
                        authSession: environment.authSession,
                        registrationURL: MusicWebConfiguration.registrationURL(
                            infoDictionary: Bundle.main.infoDictionary ?? [:]
                        ),
                        passwordResetURL: MusicWebConfiguration.passwordResetURL(
                            infoDictionary: Bundle.main.infoDictionary ?? [:]
                        )
                    ) {
                        await environment.completeAuthentication()
                    }
                }
            }
            .navigationTitle(environment.authSession.isAuthenticated ? "账号" : "登录")
            .musicInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        environment.authentication.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents(environment.authSession.isAuthenticated ? [.medium] : [.large])
    }

    private var authenticatedContent: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)
            MusicAccountAvatar(user: environment.authSession.user, size: 88)

            if let user = environment.authSession.user {
                VStack(spacing: 6) {
                    Text(user.resolvedDisplayName)
                        .font(.title2.bold())
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }

            Spacer()

            Button(role: .destructive) {
                environment.logout()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 420)
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

private struct MusicAccountAvatar: View {
    let user: AuthUser?
    let size: CGFloat

    var body: some View {
        Group {
            if let avatarURL = user?.avatarURL,
               let url = URL(string: avatarURL),
               !avatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .background(Color.musicSurface)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Group {
            if let initial = user?.resolvedDisplayName.first {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Color.musicBackground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.musicAccent)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
