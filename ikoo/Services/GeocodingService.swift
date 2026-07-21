import Foundation
import MapKit

enum GeocodingService {
    /// POI-biased search seeded with a free-text query, optionally biased
    /// around a coordinate (user location or an LLM city hint later).
    static func search(_ query: String, near center: CLLocationCoordinate2D? = nil) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
    }
}
