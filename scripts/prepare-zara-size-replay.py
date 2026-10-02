# Isolated replay: production parser/normalizer with minimal value-model stand-ins.
# Does not run SwiftData, UI, RPCs, or registration.
from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'FitMatch/Services/ZARAParser.swift').read_text()
parser=s[s.index('private enum ZARASizeGuideParser {'):s.index('\nenum ZARACategoryClassifier {')]
p=(r/'FitMatch/Services/ProductURLParserService.swift').read_text()
stable=p[p.index('extension ParsedProductSize {'):p.index('\nenum ParsedProductSizeNormalizer {')]
stubs='''import Foundation
enum ProductURLParserError: Error { case automaticParsingUnavailable }
enum ClothingCategory { case top,outer,other,bottom,dress; var serviceGroup: Self { self } }
enum MeasurementCode: String { case unknown,chestWidthPitToPit,sleeveShoulderSeamToCuff,waistWidthEdgeToEdge,hipWidthAtWidest,riseCrotchToWaistFront }
enum MeasurementDisplayKind { case unknown,shoulder,chest,totalLength,sleeveLength,waist,hip,thigh,rise,hem }
enum InputSource { case importedSizeChart }
enum EvidenceLevel { case unknown,officialText }
enum SemanticStatus { case unknownDefinition,mapped }
struct ParsedMeasurement { let value:Double; let measurementCode:MeasurementCode; let displayKind:MeasurementDisplayKind; let methodSource:String; let methodProfile:String; let inputSource:InputSource; let mappingVersion:String; let rawCode:String; let rawLabel:String; let rawInfo:String?; let rawValueText:String; let evidenceLevel:EvidenceLevel; let semanticStatus:SemanticStatus }
struct GarmentMeasurements { let shoulder:Double; let chest:Double; let totalLength:Double; let sleeveLength:Double; let waist:Double; let hip:Double; let thigh:Double; let rise:Double; let hem:Double }
struct ParsedProductSize { let id:UUID; let name:String; let measurements:GarmentMeasurements; let measurementRecords:[ParsedMeasurement] }
enum ParsedProductSizeNormalizer { static func normalizedSizeKey(for name:String)->String { SizeTokenNormalizer.normalizedKey(for:name) } }
'''
main='''
let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String:Any]]
for row in rows {
 let key = (row["audit_case_id"] ?? row["source_product_key"]) as! String
 let category: ClothingCategory
 switch row["audit_category"] as? String {
 case "bottom": category = .bottom
 case "dress": category = .dress
 case "outer": category = .outer
 default: category = key == "547804819" ? .bottom : .top
 }
 let data = try JSONSerialization.data(withJSONObject: row["measurements"]!)
 let parsed = try ZARASizeGuideParser.parseActualGarmentMeasurements(data:data,category:category)
 let expected = ((row["measurements"] as! [String:Any])["measureGuideInfo"] as! [String:Any])["sizes"] as! [[String:Any]]
 precondition(parsed.map(\\.name) == expected.map { $0["name"] as! String })
 precondition(Set(parsed.map(\\.id)).count == parsed.count)
 precondition(Set(parsed.map { SizeTokenNormalizer.normalizedKey(for:$0.name) }).count == parsed.count)
 precondition(parsed.allSatisfy { !$0.measurementRecords.isEmpty })
 print("PASS \\(key): \\(parsed.count) sizes; exact labels, unique identities, positive garment records")
}
'''
Path('/tmp/zara-size-replay.swift').write_text(stubs+(r/'FitMatch/Services/SizeTokenNormalizer.swift').read_text()+stable+parser+main)
