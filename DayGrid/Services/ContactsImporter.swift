import Contacts
import DayGridCore
import Foundation
import SwiftData

/// 연락처의 생일(양력·음력)을 `Person`으로 가져온다.
/// 이미 가져온 연락처는 `contactIdentifier`로 찾아 이름과 생일을 갱신한다.
/// iOS 18의 "일부 연락처만 허용"이면 허용한 연락처만 읽힌다.
enum ContactsImporter {
    enum ImportError: Error {
        case accessDenied
    }

    struct ContactBirthday: Sendable {
        let identifier: String
        let name: String
        let birthday: Birthday
        let birthYear: Int
    }

    struct Summary {
        var added = 0
        var updated = 0

        var text: String {
            added == 0 && updated == 0 ? "생일이 적힌 연락처가 없습니다." : "\(added)명을 추가하고 \(updated)명을 갱신했습니다."
        }
    }

    @MainActor
    static func importBirthdays(into context: ModelContext) async throws -> Summary {
        let granted = try await CNContactStore().requestAccess(for: .contacts)
        guard granted else { throw ImportError.accessDenied }
        let contacts = try await Task.detached(priority: .userInitiated) {
            try readBirthdays()
        }.value

        let existing = try context.fetch(FetchDescriptor<Person>())
        var byIdentifier: [String: Person] = [:]
        for person in existing {
            if let identifier = person.contactIdentifier {
                byIdentifier[identifier] = person
            }
        }

        var summary = Summary()
        for contact in contacts {
            if let person = byIdentifier[contact.identifier] {
                person.name = contact.name
                person.birthday = contact.birthday
                person.birthYear = contact.birthYear
                summary.updated += 1
            } else {
                let person = Person(name: contact.name, birthday: contact.birthday, birthYear: contact.birthYear)
                person.contactIdentifier = contact.identifier
                context.insert(person)
                summary.added += 1
            }
        }
        try context.save()
        return summary
    }

    /// 연락처 전체를 훑는다. 오래 걸릴 수 있으므로 메인 스레드 밖에서 부른다.
    static func readBirthdays() throws -> [ContactBirthday] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactNonGregorianBirthdayKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var result: [ContactBirthday] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            guard let found = birthday(of: contact) else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            result.append(ContactBirthday(
                identifier: contact.identifier,
                name: name.isEmpty ? "이름 없음" : name,
                birthday: found.birthday,
                birthYear: found.year
            ))
        }
        return result
    }

    /// 음력 생일이 있으면 그것을, 없으면 양력 생일을 쓴다. 태어난 해는 양력 생일에서만 읽는다(모르면 0).
    static func birthday(of contact: CNContact) -> (birthday: Birthday, year: Int)? {
        if let lunar = contact.nonGregorianBirthday,
           let calendar = lunar.calendar,
           isLunarCalendar(calendar.identifier),
           let month = lunar.month, let day = lunar.day {
            return (Birthday(month: month, day: day, isLunar: true, isLeapMonth: lunar.isLeapMonth ?? false), 0)
        }
        if let solar = contact.birthday, let month = solar.month, let day = solar.day {
            let year = solar.year.flatMap { (1...9999).contains($0) ? $0 : nil } ?? 0
            return (Birthday(month: month, day: day), year)
        }
        return nil
    }

    /// 연락처 앱의 음력 생일은 중국 음력(또는 단기)으로 저장된다.
    private static func isLunarCalendar(_ identifier: Calendar.Identifier) -> Bool {
        let name = String(describing: identifier).lowercased()
        return name.contains("chinese") || name.contains("dangi")
    }
}
