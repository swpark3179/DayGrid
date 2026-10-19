import SwiftUI

struct InboxTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "나중에 할일",
                systemImage: "tray",
                description: Text("날짜를 정하지 않은 할일을 모아 두는 곳입니다.")
            )
            .navigationTitle("나중에")
        }
    }
}
