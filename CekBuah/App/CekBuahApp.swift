import SwiftData
import SwiftUI
import UserNotifications

@main
struct CekBuahApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [LogEntry.self, StockItem.self, StockOutcome.self])
    }
}

/// A photo picked or taken by the user, ready for classification.
struct CapturedPhoto: Hashable, Identifiable {
    let id = UUID()
    let image: UIImage

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum Route: Hashable {
    case camera
    case result(CapturedPhoto)
    case shelfScan(CapturedPhoto)
    case liveScan
    case basket
    case physicalCheck(Fruit)
    case log
    case stock
    case credits
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func push(_ route: Route) { path.append(route) }
    func popToRoot() { path.removeAll() }
}

struct RootView: View {
    @State private var router = Router()
    @State private var basket = Basket()

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .camera: CameraView()
                    case .result(let photo): ResultView(photo: photo)
                    case .shelfScan(let photo): ShelfScanView(photo: photo)
                    case .liveScan: LiveScanView()
                    case .basket: BasketView()
                    case .physicalCheck(let fruit): PhysicalCheckView(fruit: fruit)
                    case .log: LogView()
                    case .stock: StockView()
                    case .credits: CreditsView()
                    }
                }
        }
        .environment(router)
        .environment(basket)
    }
}
