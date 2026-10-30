import SwiftUI

struct ContactsView: View {
    @ObservedObject var store: GuardiaStore
    @State private var showAdd = false
    @State private var editing: TrustedContact?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.contacts) { contact in
                        Button { editing = contact } label: { HStack(spacing: 16) {
                            Text(contact.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
                                .font(.headline).foregroundStyle(GuardiaStyle.accent).frame(width: 48, height: 48)
                                .background(GuardiaStyle.accent.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 5) { Text(contact.name).font(.headline); Text(contact.phone).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4) }.buttonStyle(.plain).accessibilityHint("Edit contact")
                    }.onDelete(perform: store.deleteContacts)
                    if store.contacts.count < 3 { Button { showAdd = true } label: { Label("Add Contact", systemImage: "plus.circle") } }
                } footer: { Text("Keep up to three people close. Share your journey or send a help message during a trip.") }
            }.guardiaSurface().navigationTitle("Trusted contacts").toolbar { EditButton().disabled(store.contacts.isEmpty) }
                .sheet(item: $editing) { EditContactView(store: store, contact: $0).presentationSizing(.form) }
                .sheet(isPresented: $showAdd) { AddContactView(store: store).presentationSizing(.form) }
        }
    }
}

private struct AddContactView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                TextField("Phone number", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
            }.guardiaSurface(width: 620).navigationTitle("Add contact").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.addContact(name: name, phone: phone) { dismiss() } }
                        .disabled(!ContactValidation.isValid(name: name, phone: phone))
                }
            }
        }
    }
}

private struct EditContactView: View {
    @ObservedObject var store: GuardiaStore
    @Environment(\.dismiss) private var dismiss
    @State var contact: TrustedContact
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $contact.name).textContentType(.name)
                TextField("Phone", text: $contact.phone).keyboardType(.phonePad)
            }.guardiaSurface(width: 620).navigationTitle("Edit contact").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.updateContact(contact) { dismiss() } }.disabled(!ContactValidation.isValid(name: contact.name, phone: contact.phone))
                }
            }
        }
    }
}
