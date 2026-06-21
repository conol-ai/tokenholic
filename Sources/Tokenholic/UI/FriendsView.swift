import SwiftUI
import AppKit

/// Friend management: the Share toggle, your handle, add-by-@handle, incoming /
/// outgoing requests, the shareable invite link, and the friends list. Binds to
/// `AppModel` and calls its forwarders; all mutations live in this window.
struct FriendsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var handleQuery = ""
    @State private var redeemText = ""
    @State private var renaming = false
    @State private var renameText = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            shareToggleCard
            myHandleCard
            addByHandle
            if !model.incomingRequests.isEmpty {
                requestSection("Requests for you", model.incomingRequests, incoming: true)
            }
            if !model.outgoingRequests.isEmpty {
                requestSection("Sent", model.outgoingRequests, incoming: false)
            }
            inviteCard
            friendsList
        }
    }

    // MARK: - Share toggle (privacy control)

    private var shareToggleCard: some View {
        HStack(spacing: 11) {
            GlyphTile(systemName: model.shareDaily ? "eye" : "eye.slash",
                      tint: model.shareDaily ? Palette.green : Palette.amber, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Share my daily total with friends")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(model.shareDaily ? "You appear on your friends' leaderboards."
                                      : "You're hidden — you still see them, they don't see you.")
                    .font(.system(size: 11)).foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { model.shareDaily }, set: { model.setShareDaily($0) }))
                .labelsHidden().toggleStyle(.switch).tint(Palette.green)
        }
        .cardSurface()
    }

    // MARK: - My handle

    private var myHandleCard: some View {
        VStack(alignment: .leading, spacing: renaming ? 9 : 0) {
            HStack(spacing: 10) {
                AvatarBadge(handle: model.myHandle, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your handle").font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                    Text(model.myHandle.map { "@\($0)" } ?? "—")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.ink)
                }
                Spacer()
                Button(renaming ? "Cancel" : "Edit") {
                    renameText = model.myHandle ?? ""
                    renaming.toggle()
                }
                .buttonStyle(GhostButtonStyle())
            }
            if renaming {
                HStack(spacing: 8) {
                    handleField(text: $renameText, onSubmit: saveRename)
                    Button("Save", action: saveRename)
                        .buttonStyle(PhosphorButtonStyle())
                        .disabled(renameText.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
        }
        .cardSurface()
    }

    private func saveRename() {
        let h = renameText.trimmingCharacters(in: .whitespaces)
        guard h.count >= 3 else { return }
        model.claimHandle(h)
        renaming = false
    }

    // MARK: - Add by @handle

    private var addByHandle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a friend").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 8) {
                handleField(text: $handleQuery, onSubmit: sendRequest)
                Button("Request", action: sendRequest)
                    .buttonStyle(PhosphorButtonStyle())
                    .disabled(handleQuery.trimmingCharacters(in: .whitespaces).count < 3)
            }
        }
        .cardSurface()
    }

    private func sendRequest() {
        let h = handleQuery.trimmingCharacters(in: .whitespaces)
        guard h.count >= 3 else { return }
        model.sendFriendRequest(toHandle: h)
        handleQuery = ""
    }

    // MARK: - Requests

    private func requestSection(_ title: String, _ reqs: [RequestRow], incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkDim)
            ForEach(reqs) { r in
                HStack(spacing: 10) {
                    AvatarBadge(handle: r.handle, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.display_name ?? (r.handle.map { "@\($0)" } ?? "Someone"))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                        Text(r.handle.map { "@\($0)" } ?? "—")
                            .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer(minLength: 6)
                    if incoming {
                        Button("Accept") { model.acceptRequest(r.request_id) }
                            .buttonStyle(PhosphorButtonStyle())
                        Button("Decline") { model.declineRequest(r.request_id) }
                            .buttonStyle(GhostButtonStyle())
                    } else {
                        Text("Pending").font(.system(size: 11)).foregroundStyle(Palette.amber)
                        Button("Cancel") { model.declineRequest(r.request_id) }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .cardSurface()
    }

    // MARK: - Invite by link

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Invite by link", systemImage: "link")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkDim)

            if let invite = model.currentInvite, let url = invite.url {
                HStack(spacing: 8) {
                    Text(invite.code)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.green).lineLimit(1).truncationMode(.middle)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.bgDeep))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.stroke, lineWidth: 1))
                    Button(copied ? "Copied" : "Copy") { copy(url) }
                        .buttonStyle(GhostButtonStyle())
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(GhostButtonStyle())
                }
                HStack(spacing: 6) {
                    Text("Single-use, expires in 24h.")
                        .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Button("New link") { model.createInvite() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.green)
                }
            } else {
                Button {
                    model.createInvite()
                } label: {
                    Label("Generate invite link", systemImage: "sparkles")
                }
                .buttonStyle(GhostButtonStyle())
            }

            Divider().overlay(Palette.strokeSoft)
            Text("Have a code or link?").font(.system(size: 11)).foregroundStyle(Palette.inkDim)
            HStack(spacing: 8) {
                TextField("paste invite code or link", text: $redeemText)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Palette.ink)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.bgDeep))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.stroke, lineWidth: 1))
                    .onSubmit(redeem)
                Button("Redeem", action: redeem)
                    .buttonStyle(PhosphorButtonStyle())
                    .disabled(redeemText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .cardSurface()
    }

    private func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
    }

    private func redeem() {
        let c = redeemText.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        model.redeemInvite(code: c)
        redeemText = ""
    }

    // MARK: - Friends list

    private var friendsList: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Friends · \(model.friends.count)")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.inkDim)
            if model.friends.isEmpty {
                Text("No friends yet. Add one above to start a daily board.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.inkFaint)
            } else {
                ForEach(model.friends) { f in
                    HStack(spacing: 10) {
                        AvatarBadge(handle: f.handle, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.display_name ?? (f.handle.map { "@\($0)" } ?? "Friend"))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                            Text(f.handle.map { "@\($0)" } ?? "—")
                                .font(.system(size: 11)).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        if !f.sharing {
                            Image(systemName: "eye.slash").font(.system(size: 11))
                                .foregroundStyle(Palette.inkFaint).help("Hidden — they aren't sharing their total")
                        }
                        Menu {
                            Button("Remove friend", role: .destructive) { model.removeFriend(f.user_id) }
                            Button("Block", role: .destructive) { model.blockUser(f.user_id) }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Palette.inkFaint)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .cardSurface()
    }

    // MARK: - Shared handle text field

    private func handleField(text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text("@").foregroundStyle(Palette.inkFaint)
            TextField("handle", text: text)
                .textFieldStyle(.plain).foregroundStyle(Palette.ink)
                .onSubmit(onSubmit)
        }
        .font(.system(size: 13)).padding(.horizontal, 11).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.bgDeep))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.stroke, lineWidth: 1))
    }
}
