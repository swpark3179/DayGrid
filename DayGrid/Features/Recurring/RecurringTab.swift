import SwiftUI

struct RecurringTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "반복 할일",
                systemImage: "repeat",
                description: Text("매일, 매주, 매월 해야 할 일을 관리하는 곳입니다.")
            )
            .navigationTitle("반복")
        }
    }
}
