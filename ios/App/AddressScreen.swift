import CoreLocation
import SwiftUI

@MainActor
final class LocationOnce: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?
    private var asked = false
    private var requested = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locate() async -> CLLocation? {
        finish(nil)
        return await withCheckedContinuation { continuation in
            waiting = continuation
            requested = false
            advance()
        }
    }

    private func advance() {
        guard waiting != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            if !asked {
                asked = true
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            finish(nil)
        default:
            if !requested {
                requested = true
                manager.requestLocation()
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        let continuation = waiting
        waiting = nil
        continuation?.resume(returning: location)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { advance() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { finish(locations.last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }
}

struct AddressScreen: View {
    let group: OutageGroup?
    let onSave: (OutageGroup?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var street = ""
    @State private var streets: [YasnoChoice] = []
    @State private var picked: YasnoChoice?
    @State private var house = ""
    @State private var fromLocation = false
    @State private var houses: [YasnoChoice] = []
    @State private var note: LocalizedStringKey?
    @State private var busy = false

    private struct HouseQuery: Equatable {
        var street: Int?
        var text: String
    }

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await useLocation() }
                } label: {
                    HStack {
                        Label("Use my location", systemImage: "location")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
            } footer: {
                Text("The app keeps only the group and the address text, not your location.")
            }

            Section("Street") {
                TextField("Street", text: Binding(get: { street }, set: { if $0 != street { fromLocation = false }; street = $0 }))
                    .autocorrectionDisabled()
                ForEach(streets) { choice in
                    Button(choice.value) {
                        picked = choice
                        streets = []
                        note = nil
                    }
                    .foregroundStyle(.primary)
                }
                if let picked {
                    Label(picked.value, systemImage: "checkmark").foregroundStyle(.secondary)
                }
            }

            if let picked {
                Section("House") {
                    TextField("House", text: Binding(get: { house }, set: { if $0 != house { fromLocation = false }; house = $0 }))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    ForEach(houses) { choice in
                        Button(choice.value) {
                            Task { await save(choice, on: picked) }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .task(id: HouseQuery(street: picked.id, text: house)) { await findHouses(on: picked) }
            }

            if let note {
                Section { Text(note).foregroundStyle(.secondary) }
            }

            if let group {
                Section {
                    Text(group.address)
                    Button("Remove address", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
            }
        }
        .task(id: street) { await findStreets() }
        .navigationTitle("Address")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func useLocation() async {
        busy = true
        note = nil
        if let location = await LocationOnce().locate() {
            if let mark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "uk_UA")).first,
               let thoroughfare = mark.thoroughfare {
                house = mark.subThoroughfare ?? ""
                fromLocation = true
                street = thoroughfare
            } else {
                note = "Could not find your street. Type it."
            }
        } else {
            note = "Location is off. Type the street."
        }
        busy = false
    }

    private func findStreets() async {
        picked = nil
        streets = []
        houses = []
        let query = Address.query(street)
        guard query.filter(\.isLetter).count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        note = nil
        do {
            let found = try await YasnoClient().streets(query)
            guard !Task.isCancelled else { return }
            if let match = Address.match(street, in: found) {
                picked = match
            } else {
                streets = found
                if found.isEmpty { note = "No match. YASNO covers Kyiv city only." }
            }
        } catch {
            if !Task.isCancelled { note = "YASNO did not answer." }
        }
    }

    private func findHouses(on street: YasnoChoice) async {
        houses = []
        let query = house.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        do {
            let found = try await YasnoClient().houses(street: street.id, query: query)
            guard !Task.isCancelled else { return }
            if fromLocation, let match = Address.match(query, in: found) {
                await save(match, on: street)
            } else {
                houses = found
                if found.isEmpty { note = "No match. YASNO covers Kyiv city only." }
            }
        } catch {
            if !Task.isCancelled { note = "YASNO did not answer." }
        }
    }

    private func save(_ house: YasnoChoice, on street: YasnoChoice) async {
        do {
            let found = try await YasnoClient().group(street: street.id, house: house.id)
            onSave(OutageGroup(group: found.group, subgroup: found.subgroup, address: "\(street.value), \(house.value)"))
            dismiss()
        } catch {
            note = "YASNO did not answer."
        }
    }
}
