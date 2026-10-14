import Foundation

struct Reading: Codable, Equatable {
    var time: Date
    var socPct: Int
    var acW: Double
    var offgridW: Double
    var capacityWh: Double
    var ratedWh: Double
    var tempC: Double
}

extension Reading {
    init(time: Date, es: EsStatus, bat: BatStatus) {
        self.init(
            time: time, socPct: es.socPct, acW: es.ongridW + es.offgridW, offgridW: es.offgridW,
            capacityWh: bat.capacityWh, ratedWh: bat.ratedWh, tempC: bat.tempC
        )
    }
}
