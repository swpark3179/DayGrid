/// SwiftData(Core Data) 모델이 iCloud에 만드는 CloudKit 스키마를 스키마 언어(`.ckdb`) 텍스트로 쓴다.
///
/// TestFlight 빌드는 CloudKit Production 환경을 쓰고, Production 스키마는 자동으로 생기지 않는다.
/// 그래서 이 텍스트를 `cloudkit/DayGrid.ckdb`에 커밋하고, `cktool import-schema`로 Development에 넣은 뒤
/// CloudKit Console에서 Production으로 배포한다.
///
/// 매핑은 Apple 문서 "Reading CloudKit Records for Core Data"를 따른다.
/// - 엔티티 → 레코드 타입 `CD_<엔티티>`, 속성 → 필드 `CD_<속성>`
/// - 모든 레코드에 `CD_entityName`(현재 엔티티 이름)과 `CD_moveReceipt`(+`_ckAsset`)가 붙는다.
/// - 길이가 정해지지 않은 속성(String, Binary Data)은 1MB가 넘을 때 쓰는 `CD_<속성>_ckAsset` 필드가 하나 더 생긴다.
/// - to-one 관계는 상대 레코드 이름을 담는 STRING 필드다. to-many 관계는 필드가 없다(상대 쪽 to-one이 담는다).
public enum CloudKitSchemaFile {
    /// Core Data 속성 종류
    public enum AttributeKind: Hashable, Sendable {
        case string
        case binary
        case uuid
        case uri
        case integer
        case boolean
        case double
        case decimal
        case date
    }

    public struct Attribute: Hashable, Sendable {
        public let name: String
        public let kind: AttributeKind

        public init(name: String, kind: AttributeKind) {
            self.name = name
            self.kind = kind
        }
    }

    public struct Entity: Hashable, Sendable {
        public let name: String
        public let attributes: [Attribute]
        /// to-one 관계 이름
        public let toOneRelationships: [String]

        public init(name: String, attributes: [Attribute], toOneRelationships: [String]) {
            self.name = name
            self.attributes = attributes
            self.toOneRelationships = toOneRelationships
        }
    }

    public struct Field: Hashable, Sendable {
        public let name: String
        /// 스키마 언어의 타입: STRING, BYTES, INT64, DOUBLE, TIMESTAMP, ASSET
        public let type: String
    }

    public static func recordTypeName(of entity: Entity) -> String {
        "CD_\(entity.name)"
    }

    /// 레코드 타입의 필드(이름 순)
    public static func fields(of entity: Entity) -> [Field] {
        var fields = [
            Field(name: "CD_entityName", type: "STRING"),
            Field(name: "CD_moveReceipt", type: "BYTES"),
            Field(name: "CD_moveReceipt_ckAsset", type: "ASSET"),
        ]
        for attribute in entity.attributes {
            let name = "CD_\(attribute.name)"
            switch attribute.kind {
            case .string:
                fields.append(Field(name: name, type: "STRING"))
                fields.append(Field(name: "\(name)_ckAsset", type: "ASSET"))
            case .binary:
                fields.append(Field(name: name, type: "BYTES"))
                fields.append(Field(name: "\(name)_ckAsset", type: "ASSET"))
            case .uuid, .uri:
                fields.append(Field(name: name, type: "STRING"))
            case .integer, .boolean:
                fields.append(Field(name: name, type: "INT64"))
            case .double, .decimal:
                fields.append(Field(name: name, type: "DOUBLE"))
            case .date:
                fields.append(Field(name: name, type: "TIMESTAMP"))
            }
        }
        for relationship in entity.toOneRelationships {
            fields.append(Field(name: "CD_\(relationship)", type: "STRING"))
        }
        return fields.sorted { $0.name < $1.name }
    }

    /// `.ckdb` 텍스트. 레코드 타입은 이름 순이고, 컨테이너마다 있는 `Users` 타입을 함께 적는다.
    public static func render(_ entities: [Entity]) -> String {
        var lines = [
            "// DayGrid CloudKit schema. Generated from the SwiftData models; do not edit by hand.",
            "// Update it with the CloudKitSchemaTests output, then run the \"CloudKit schema\" workflow.",
            "DEFINE SCHEMA",
            "",
        ]
        for entity in entities.sorted(by: { $0.name < $1.name }) {
            lines.append("    RECORD TYPE \(recordTypeName(of: entity)) (")
            lines += systemFields.map { "        \($0)," }
            lines += fields(of: entity).map { "        \($0.name) \($0.type)," }
            lines += [
                "        GRANT WRITE TO \"_creator\",",
                "        GRANT CREATE TO \"_icloud\",",
                "        GRANT READ TO \"_world\"",
                "    );",
                "",
            ]
        }
        lines += [
            "    RECORD TYPE Users (",
        ]
        lines += systemFields.map { "        \($0)," }
        lines += [
            "        roles LIST<INT64>,",
            "        GRANT WRITE TO \"_creator\",",
            "        GRANT READ TO \"_world\"",
            "    );",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static let systemFields = [
        "\"___createTime\" TIMESTAMP",
        "\"___createdBy\" REFERENCE",
        "\"___etag\" STRING",
        "\"___modTime\" TIMESTAMP",
        "\"___modifiedBy\" REFERENCE",
        "\"___recordID\" REFERENCE QUERYABLE",
    ]
}
