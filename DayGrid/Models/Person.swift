import DayGridCore
import Foundation
import SwiftData

/// 생일을 챙길 사람. 연락처에서 가져온 사람과 직접 입력한 사람을 함께 담는다.
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var birthMonth: Int = 1
    var birthDay: Int = 1
    /// 태어난 해(양력 생일일 때만). 0이면 모른다.
    var birthYear: Int = 0
    var isLunar: Bool = false
    var isLeapMonth: Bool = false
    /// 연락처에서 가져왔으면 그 연락처의 식별자. 다시 가져올 때 같은 사람을 찾는 데 쓴다.
    var contactIdentifier: String?
    var createdAt: Date = Date()

    init(name: String, birthday: Birthday, birthYear: Int = 0) {
        self.name = name
        self.birthYear = birthYear
        self.birthday = birthday
    }
}

extension Person {
    var birthday: Birthday {
        get { Birthday(month: birthMonth, day: birthDay, isLunar: isLunar, isLeapMonth: isLeapMonth) }
        set {
            birthMonth = newValue.month
            birthDay = newValue.day
            isLunar = newValue.isLunar
            isLeapMonth = newValue.isLeapMonth
        }
    }

    /// `date`가 생일이면 "n번째 생일"(태어난 해를 알 때만).
    func ordinalText(on date: LocalDate) -> String? {
        guard birthYear > 0, !isLunar, date.year > birthYear else { return nil }
        return "\(date.year - birthYear)번째 생일"
    }
}
