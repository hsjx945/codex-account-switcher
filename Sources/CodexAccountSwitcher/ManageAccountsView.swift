import SwiftUI

struct ManageAccountsView: View {
    @ObservedObject var model: AppModel
    let onBack: () -> Void

    @State private var page: ManageAccountsPage = .accounts

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(
                title: headerTitle,
                backTitle: model.text("back"),
                onBack: navigateBack
            )

            Divider()

            switch page {
            case .accounts:
                accountList
            case .add:
                addAccountPage
            case let .edit(account):
                NicknameEditor(model: model, account: account) {
                    page = .accounts
                }
            case let .remove(account):
                removePage(account)
            }
        }
        .onChange(of: model.isAddingAccount) { wasAdding, isAdding in
            if wasAdding, !isAdding, case .add = page {
                page = .accounts
            }
        }
    }

    private var headerTitle: String {
        switch page {
        case .accounts:
            model.text("manage")
        case .add:
            model.text("add_account")
        case .edit:
            model.text("edit_nickname")
        case .remove:
            model.text("remove_account")
        }
    }

    private func navigateBack() {
        switch page {
        case .accounts:
            onBack()
        case .add:
            model.cancelAddingAccount()
            page = .accounts
        case .edit, .remove:
            page = .accounts
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            if model.accounts.isEmpty {
                ContentUnavailableView(
                    model.text("no_accounts"),
                    systemImage: "person.crop.circle.badge.plus"
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.displayedAccounts) { account in
                            ManagedAccountRow(
                                model: model,
                                account: account,
                                onEdit: { page = .edit(account) },
                                onRemove: { page = .remove(account) }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 520)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    page = .add
                    model.addAccount()
                } label: {
                    Label(model.text("add_account"), systemImage: "plus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .disabled(model.isMutating || model.isAddingAccount)

                Text(model.text("sign_in_hint"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(9)
        }
    }

    private var addAccountPage: some View {
        VStack(spacing: 17) {
            ProgressView()
                .controlSize(.large)
                .tint(.orange)

            VStack(spacing: 6) {
                Text(model.text("waiting_for_sign_in"))
                    .font(.system(size: 15, weight: .bold))
                Text(model.text("sign_in_pending_hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(model.text("cancel_add_account")) {
                model.cancelAddingAccount()
                page = .accounts
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(24)
    }

    private func removePage(_ account: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Image(systemName: "trash")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 42, height: 42)
                .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

            Text(model.format("remove_title", account.preferredLabel))
                .font(.system(size: 18, weight: .bold))

            Text(model.text("remove_body"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(model.text("cancel")) { page = .accounts }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button(model.text("remove"), role: .destructive) {
                    page = .accounts
                    Task { await model.removeAccount(id: account.id) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(model.isMutating)
            }
        }
        .padding(16)
    }
}

private enum ManageAccountsPage {
    case accounts
    case add
    case edit(AccountProfile)
    case remove(AccountProfile)
}

private struct ManagedAccountRow: View {
    @ObservedObject var model: AppModel
    let account: AccountProfile
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.preferredLabel)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if account.nickname?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                   let email = account.email {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 6)

            if account.id == model.activeAccountID {
                Text(model.text("active"))
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color(red: 0.05, green: 0.34, blue: 0.16))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(
                        Color(red: 0.80, green: 0.94, blue: 0.85),
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }

            Button(action: onEdit) {
                Label(model.text("set_remark"), systemImage: "pencil")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(model.text("edit_nickname"))
            .accessibilityLabel(model.text("edit_nickname"))
            .disabled(model.isMutating)

            if account.id != model.activeAccountID {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(model.format("remove_title", account.preferredLabel))
                .accessibilityLabel(model.format("remove_title", account.preferredLabel))
                .disabled(model.isMutating)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 58)
        .background(
            Color.primary.opacity(isHovering ? 0.045 : 0),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .onHover { isHovering = $0 }
    }
}

private struct NicknameEditor: View {
    @ObservedObject var model: AppModel
    let account: AccountProfile
    let onDone: () -> Void
    @State private var nickname: String

    init(model: AppModel, account: AccountProfile, onDone: @escaping () -> Void) {
        self.model = model
        self.account = account
        self.onDone = onDone
        _nickname = State(initialValue: account.nickname ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let email = account.email {
                Text(email)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                    .textSelection(.enabled)
            }

            Text(model.text("nickname"))
                .font(.system(size: 11, weight: .semibold))

            TextField(model.text("nickname"), text: $nickname)
                .textFieldStyle(.roundedBorder)

            Text(model.text("nickname_hint"))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(model.text("cancel"), action: onDone)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button(model.text("save")) {
                    Task {
                        if await model.updateNickname(id: account.id, nickname: nickname) {
                            onDone()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(model.isMutating)
            }
        }
        .padding(16)
    }
}

struct PopoverHeader: View {
    let title: String
    let backTitle: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(backTitle)
            .help(backTitle)

            Spacer()

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Spacer()

            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 52)
    }
}
