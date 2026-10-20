import CoreData
import DayGridCore
import Foundation
import SwiftData
import Testing
@testable import DayGrid

/// SwiftData 모델과 커밋된 CloudKit 스키마(`cloudkit/DayGrid.ckdb`)가 같은지 본다.
/// TestFlight 빌드는 Production 스키마를 쓰므로, 모델을 바꾸고 스키마를 갱신하지 않으면 기기에서 동기화가 멈춘다.
@MainActor
struct CloudKitSchemaTests {
    /// SwiftData가 Core Data에 넘기는 모델(Apple 문서의 CloudKit 스키마 초기화와 같은 방법)
    private func makeModel() throws -> NSManagedObjectModel {
        try #require(NSManagedObjectModel.makeManagedObjectModel(for: AppModelContainer.modelTypes))
    }

    @Test func committedSchemaMatchesTheModels() throws {
        var unsupported: [String] = []
        let entities = try makeModel().entities.map { entity -> CloudKitSchemaFile.Entity in
            let name = try #require(entity.name)
            let attributes = entity.attributesByName.values.compactMap { attribute -> CloudKitSchemaFile.Attribute? in
                guard let kind = Self.kind(of: attribute) else {
                    unsupported.append("\(name).\(attribute.name)")
                    return nil
                }
                return CloudKitSchemaFile.Attribute(name: attribute.name, kind: kind)
            }
            let toOne = entity.relationshipsByName.values.filter { !$0.isToMany }.map(\.name)
            return CloudKitSchemaFile.Entity(name: name, attributes: attributes, toOneRelationships: toOne)
        }
        #expect(unsupported.isEmpty, "CloudKit에 저장할 수 없는 속성: \(unsupported)")
        #expect(Set(entities.map(\.name)) == ["ItemCategory", "Item", "PersonalHoliday", "Person", "RecurringTask", "RecurrenceCompletion"])

        let generated = CloudKitSchemaFile.render(entities)
        let committed = try String(contentsOf: Self.committedSchemaURL, encoding: .utf8)
        #expect(
            generated == committed,
            "cloudkit/DayGrid.ckdb가 모델과 다르다. 아래 내용으로 바꾸고 CloudKit 스키마 워크플로를 다시 실행한다.\n\(generated)"
        )
    }

    /// CloudKit이 받아들이는 모델인지(관계는 optional이고 반대쪽이 있으며, unique 제약이 없다).
    @Test func modelsFollowTheCloudKitRules() throws {
        for entity in try makeModel().entities {
            let name = entity.name ?? "?"
            #expect(entity.uniquenessConstraints.isEmpty, "\(name)에 unique 제약이 있다")
            for relationship in entity.relationshipsByName.values {
                #expect(relationship.isOptional, "\(name).\(relationship.name)는 optional이어야 한다")
                #expect(relationship.inverseRelationship != nil, "\(name).\(relationship.name)에 반대쪽 관계가 있어야 한다")
                #expect(relationship.deleteRule != .denyDeleteRule, "\(name).\(relationship.name)에 deny 삭제 규칙을 쓸 수 없다")
            }
        }
    }

    /// 저장소의 컨테이너 ID와 entitlements가 같은 값인지
    @Test func containerIDMatchesTheEntitlements() throws {
        let url = Self.repositoryRoot.appending(path: "DayGrid/DayGrid.entitlements")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any]
        let containers = plist?["com.apple.developer.icloud-container-identifiers"] as? [String]
        #expect(containers == [AppModelContainer.cloudKitContainerID])
        #expect(plist?["com.apple.developer.icloud-services"] as? [String] == ["CloudKit"])
    }

    private static func kind(of attribute: NSAttributeDescription) -> CloudKitSchemaFile.AttributeKind? {
        switch attribute.type {
        case .string: .string
        case .uuid: .uuid
        case .uri: .uri
        case .integer16, .integer32, .integer64: .integer
        case .boolean: .boolean
        case .double, .float: .double
        case .decimal: .decimal
        case .date: .date
        case .binaryData, .transformable: .binary
        default: nil
        }
    }

    /// 시뮬레이터는 Mac의 파일을 읽을 수 있으므로 저장소의 파일을 바로 읽는다.
    private static var repositoryRoot: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static var committedSchemaURL: URL {
        repositoryRoot.appending(path: "cloudkit/DayGrid.ckdb")
    }
}
