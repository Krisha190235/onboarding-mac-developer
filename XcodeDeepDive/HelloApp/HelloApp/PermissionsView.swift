// 8.2 Permission Request App
//
// Requests two TCC-protected permissions — Camera (AVFoundation) and Contacts
// (Contacts framework) — and shows the full lifecycle for each: current status,
// the request itself, what to do when the user says no, and proof that the
// grant actually works.
//
// Requirements that live outside this file:
//   • Info.plist purpose strings (INFOPLIST_KEY_NSCameraUsageDescription and
//     INFOPLIST_KEY_NSContactsUsageDescription build settings). Missing one is
//     a crash, not a denial.
//   • Sandbox entitlements in HelloApp.entitlements:
//     com.apple.security.device.camera and
//     com.apple.security.personal-information.addressbook.

import SwiftUI
import AVFoundation
import Contacts
import AppKit

// MARK: - A permission's state, in the app's own vocabulary

/// The subset of states the UI actually cares about. Both frameworks report
/// their own enum; mapping them to one type keeps the view simple.
enum PermissionState {
    case notDetermined   // never asked — a request will show the system alert
    case granted
    case denied          // user said no, or an admin restricted it
    case unknown         // a case Apple added after this was written

    var label: String {
        switch self {
        case .notDetermined: return "Not requested yet"
        case .granted:       return "Granted"
        case .denied:        return "Denied"
        case .unknown:       return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .granted:       return .green
        case .denied:        return .red
        case .notDetermined: return .secondary
        case .unknown:       return .orange
        }
    }

    /// Only `.notDetermined` can produce a system prompt. Once the user has
    /// answered, the only way to change the answer is System Settings.
    var canPrompt: Bool { self == .notDetermined }
}

// MARK: - Camera

enum CameraPermission {
    static var state: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:            return .notDetermined
        case .authorized:               return .granted
        case .denied, .restricted:      return .denied
        @unknown default:               return .unknown
        }
    }

    /// Shows the system alert if the user hasn't been asked yet; otherwise
    /// returns the existing decision without any UI.
    @discardableResult
    static func request() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Something only possible once access is granted — proof the grant works.
    static func describeDevice() -> String {
        guard let device = AVCaptureDevice.default(for: .video) else {
            return "No video device found"
        }
        return device.localizedName
    }
}

// MARK: - Contacts

enum ContactsPermission {
    static var state: PermissionState {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:            return .notDetermined
        case .authorized:               return .granted
        case .denied, .restricted:      return .denied
        @unknown default:               return .unknown   // e.g. .limited on newer systems
        }
    }

    @discardableResult
    static func request() async -> Bool {
        do {
            return try await CNContactStore().requestAccess(for: .contacts)
        } catch {
            // A thrown error here almost always means the request couldn't be
            // made at all (missing purpose string, missing entitlement).
            print("Contacts request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Counts the contacts the app can see. Fine for a demo; a real app would
    /// do this off the main thread.
    static func contactCount() -> String {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor])
        var count = 0
        do {
            try store.enumerateContacts(with: request) { _, _ in count += 1 }
            return "\(count) contact\(count == 1 ? "" : "s") visible"
        } catch {
            return "Couldn't read contacts: \(error.localizedDescription)"
        }
    }
}

// MARK: - Settings deep links

/// A denied permission can't be re-requested — the app can only send the user
/// to the right pane of System Settings.
enum PrivacyPane: String {
    case camera = "Privacy_Camera"
    case contacts = "Privacy_Contacts"

    func open() {
        let base = "x-apple.systempreferences:com.apple.preference.security?"
        guard let url = URL(string: base + rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - View

struct PermissionsView: View {
    @State private var cameraState = CameraPermission.state
    @State private var contactsState = ContactsPermission.state
    @State private var cameraDetail = ""
    @State private var contactsDetail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Permissions (8.2)")
                    .font(.title2)
                Text("Camera and Contacts are both TCC-protected. macOS only shows an alert the first time — after that, the decision lives in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PermissionRow(
                title: "Camera",
                subtitle: "AVCaptureDevice.requestAccess(for: .video)",
                state: cameraState,
                detail: cameraDetail,
                request: {
                    await CameraPermission.request()
                    cameraState = CameraPermission.state
                    cameraDetail = cameraState == .granted ? CameraPermission.describeDevice() : ""
                },
                openSettings: { PrivacyPane.camera.open() }
            )

            Divider()

            PermissionRow(
                title: "Contacts",
                subtitle: "CNContactStore().requestAccess(for: .contacts)",
                state: contactsState,
                detail: contactsDetail,
                request: {
                    await ContactsPermission.request()
                    contactsState = ContactsPermission.state
                    contactsDetail = contactsState == .granted ? ContactsPermission.contactCount() : ""
                },
                openSettings: { PrivacyPane.contacts.open() }
            )

            Divider()

            Button("Refresh status") {
                refresh()
            }
            .help("The user can change these in System Settings while the app is running, so re-check rather than caching the answer.")
        }
        .padding(24)
        .frame(width: 460)
        .onAppear(perform: refresh)
    }

    /// Permissions can change while the app is running — never cache a grant.
    private func refresh() {
        cameraState = CameraPermission.state
        contactsState = ContactsPermission.state
        cameraDetail = cameraState == .granted ? CameraPermission.describeDevice() : ""
        contactsDetail = contactsState == .granted ? ContactsPermission.contactCount() : ""
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let state: PermissionState
    let detail: String
    let request: () async -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(state.label)
                    .font(.subheadline)
                    .foregroundStyle(state.color)
            }

            Text(subtitle)
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)

            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
            }

            HStack {
                if state.canPrompt {
                    Button("Request access") {
                        Task { await request() }
                    }
                } else if state == .denied {
                    Button("Open System Settings…", action: openSettings)
                    Text("Already denied — the app can't ask again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    PermissionsView()
}
