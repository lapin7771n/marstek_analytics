import Foundation

struct Reading: Codable, Equatable {
    var time: Date
    var socPct: Int
    var acW: Double
    var offgridW: Double
    var capacityWh: Double
    var ratedWh: Double
}

extension Reading {
    init(time: Date, es: EsStatus) {
        self.init(
            time: time, socPct: es.socPct, acW: es.ongridW + es.offgridW, offgridW: es.offgridW,
            capacityWh: Double(es.socPct) / 100 * es.ratedWh, ratedWh: es.ratedWh
        )
    }
}
