// Native MapKit equivalent of the Android catalog's markers initializer.
import SwiftUI
import MapKit

struct MapPlayground: View {
    @State private var lima = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -12.046, longitude: -77.043),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    ))
    @State private var cupertino = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.334, longitude: -122.009),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Example("Region with markers") {
                    Map(position: $lima) {
                        Marker("Plaza Mayor", coordinate: CLLocationCoordinate2D(latitude: -12.046, longitude: -77.030))
                        Marker("Miraflores", coordinate: CLLocationCoordinate2D(latitude: -12.120, longitude: -77.030)).tint(.blue)
                        Marker("Callao", coordinate: CLLocationCoordinate2D(latitude: -12.055, longitude: -77.100)).tint(.green)
                    }
                    .frame(height: 240)
                }
                Example("Plain region") {
                    Map(position: $cupertino)
                        .frame(height: 140)
                        .cornerRadius(12)
                }
            }
        }
    }
}
