import SwiftUI

/// Asks the user to confirm the fruit when recognition is not sure, or warns that the photo
/// looks like another fruit. It never blocks: the user can confirm, switch, or pick any fruit.
struct IdentityNotice: View {
    let pickedFruit: Fruit
    let identity: FruitIdentity
    var isWorking = false
    let onSwitch: (Fruit) -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(message, systemImage: identity.suggested == nil ? "questionmark.circle" : "exclamationmark.triangle")
                .font(.subheadline.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let suggested = identity.suggested {
                Button {
                    onSwitch(suggested)
                } label: {
                    if isWorking { ProgressView() } else { Text("Ganti ke \(suggested.displayName)") }
                }
                .buttonStyle(PrimaryButtonStyle(prominent: true))
            }
            Button(keepTitle, action: onKeep)
                .buttonStyle(PrimaryButtonStyle(prominent: identity.suggested == nil))
            Menu {
                ForEach(Fruit.enabled.filter { $0 != pickedFruit && $0 != identity.suggested }) { fruit in
                    Button("\(fruit.emoji) \(fruit.displayName)") { onSwitch(fruit) }
                }
            } label: {
                Label("Pilih buah lain", systemImage: "list.bullet")
            }
            .buttonStyle(PrimaryButtonStyle(prominent: false))
        }
        .disabled(isWorking)
        .card(border: Color(light: 0x9A3412, dark: 0xFB923C))
    }

    private var message: String {
        if let suggested = identity.suggested {
            return "Foto ini terlihat seperti \(suggested.displayName)."
        }
        return "Jenis buah belum pasti. Apakah ini \(pickedFruit.displayName.lowercased())?"
    }

    private var keepTitle: String {
        identity.suggested == nil ? "Ya, \(pickedFruit.displayName)" : "Tetap nilai sebagai \(pickedFruit.displayName)"
    }
}
