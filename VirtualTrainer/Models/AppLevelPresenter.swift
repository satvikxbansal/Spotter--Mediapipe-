import SwiftUI

nonisolated struct AppLevelPresentationState: Equatable {
    var isLiveWorkoutPresented = false
}

private struct AppLevelPresenterEnvironmentKey: EnvironmentKey {
    static let defaultValue: Binding<AppLevelPresentationState> = .constant(AppLevelPresentationState())
}

extension EnvironmentValues {
    var appLevelPresenter: Binding<AppLevelPresentationState> {
        get { self[AppLevelPresenterEnvironmentKey.self] }
        set { self[AppLevelPresenterEnvironmentKey.self] = newValue }
    }
}

extension Binding where Value == AppLevelPresentationState {
    func setLiveWorkoutPresented(_ isPresented: Bool) {
        guard wrappedValue.isLiveWorkoutPresented != isPresented else { return }
        wrappedValue.isLiveWorkoutPresented = isPresented
    }
}
