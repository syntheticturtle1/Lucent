import SwiftUI
import LucentCore

struct ProfilePickerView: View {
    @ObservedObject var appState: AppState
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: UUID?
    @State private var showNewProfile = false
    @State private var newProfileName = ""
    @State private var editingProfileID: UUID?
    @State private var editingName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appState.settingsManager.availableProfiles, id: \.id) { profile in
                HStack {
                    // Selection radio
                    Image(systemName: profile.id == appState.settingsManager.activeProfileID
                          ? "largecircle.fill.circle" : "circle")
                        .foregroundColor(profile.id == appState.settingsManager.activeProfileID ? .blue : .secondary)
                        .onTapGesture {
                            appState.settingsManager.switchProfile(to: profile.id)
                            appState.pipeline.applySettings(from: appState.settingsManager)
                        }

                    // Name (editable on double-click)
                    if editingProfileID == profile.id {
                        TextField("Name", text: $editingName, onCommit: {
                            commitNameEdit(profileID: profile.id)
                        })
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    } else {
                        Text(profile.name)
                            .onTapGesture(count: 2) {
                                editingProfileID = profile.id
                                editingName = profile.name
                            }
                    }

                    Spacer()

                    // Delete button (only if more than 1 profile)
                    if appState.settingsManager.availableProfiles.count > 1 {
                        Button(action: {
                            profileToDelete = profile.id
                            showDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            if showNewProfile {
                HStack {
                    TextField("Profile name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                        .onSubmit { createNewProfile() }

                    Button("Add") { createNewProfile() }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("Cancel") {
                        showNewProfile = false
                        newProfileName = ""
                    }
                }
            } else {
                Button("New Profile") {
                    showNewProfile = true
                    newProfileName = ""
                }
            }
        }
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let id = profileToDelete {
                    appState.settingsManager.deleteProfile(id: id)
                }
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this profile? This cannot be undone.")
        }
    }

    private func createNewProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = appState.settingsManager.createProfile(name: name)
        appState.settingsManager.switchProfile(to: profile.id)
        appState.pipeline.applySettings(from: appState.settingsManager)
        showNewProfile = false
        newProfileName = ""
    }

    private func commitNameEdit(profileID: UUID) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            editingProfileID = nil
            return
        }
        if let idx = appState.settingsManager.availableProfiles.firstIndex(where: { $0.id == profileID }) {
            appState.settingsManager.availableProfiles[idx].name = name
            if appState.settingsManager.currentProfile.id == profileID {
                appState.settingsManager.currentProfile.name = name
            }
            appState.settingsManager.saveCurrentProfile()
        }
        editingProfileID = nil
    }
}
