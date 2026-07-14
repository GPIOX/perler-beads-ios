import Foundation

public struct RGBColor: Codable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct PaletteColor: Codable, Hashable, Identifiable, Sendable {
    public let hex: String
    public let rgb: RGBColor
    public var id: String { hex }

    public init(hex: String) throws {
        self.hex = hex.uppercased()
        self.rgb = try RGBColor(hex: hex)
    }
}

public extension RGBColor {
    init(hex: String) throws {
        let normalized = hex.uppercased()
        guard normalized.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil,
              let value = UInt32(normalized.dropFirst(), radix: 16)
        else {
            throw PatternCoreError.invalidHex(hex)
        }
        self.init(
            red: UInt8((value >> 16) & 0xff),
            green: UInt8((value >> 8) & 0xff),
            blue: UInt8(value & 0xff)
        )
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

public struct ColorMappingStore: Sendable {
    public let mappings: [String: [ColorSystem: String]]
    public let palette: [PaletteColor]

    public init(data: Data) throws {
        let raw = try JSONDecoder().decode([String: [String: String]].self, from: data)
        guard raw.count == 291 else {
            throw PatternCoreError.invalidColorMapping("应有 291 种颜色，实际为 \(raw.count)")
        }

        var converted: [String: [ColorSystem: String]] = [:]
        var colors: [PaletteColor] = []
        for (hex, values) in raw {
            let normalized = hex.uppercased()
            let color = try PaletteColor(hex: normalized)
            var systemValues: [ColorSystem: String] = [:]
            for system in ColorSystem.allCases {
                guard let code = values[system.rawValue], !code.isEmpty else {
                    throw PatternCoreError.invalidColorMapping("\(normalized) 缺少 \(system.rawValue) 色号")
                }
                systemValues[system] = code
            }
            converted[normalized] = systemValues
            colors.append(color)
        }
        self.mappings = converted
        self.palette = colors.sorted { $0.hex < $1.hex }
    }

    public static func bundled() throws -> ColorMappingStore {
        guard let url = Bundle.module.url(forResource: "colorSystemMapping", withExtension: "json") else {
            throw PatternCoreError.invalidColorMapping("找不到 colorSystemMapping.json")
        }
        return try ColorMappingStore(data: Data(contentsOf: url))
    }

    public func code(for hex: String, system: ColorSystem) -> String? {
        mappings[hex.uppercased()]?[system]
    }

    public func activePalette(settings: PatternSettings) throws -> [PaletteColor] {
        let selected = settings.selectedHexColors.map { $0.uppercased() }
        let excluded = Set(settings.excludedHexColors.map { $0.uppercased() })
        let selectedSet = Set(selected)
        let result = palette.filter { color in
            (selectedSet.isEmpty || selectedSet.contains(color.hex)) && !excluded.contains(color.hex)
        }
        guard !result.isEmpty else { throw PatternCoreError.emptyPalette }
        return result
    }
}

struct OKLab: Sendable {
    let l: Double
    let a: Double
    let b: Double
}

public enum ColorDistance {
    public static func oklab(_ lhs: RGBColor, _ rhs: RGBColor) -> Double {
        let first = convert(lhs)
        let second = convert(rhs)
        let dl = first.l - second.l
        let da = first.a - second.a
        let db = first.b - second.b
        return (dl * dl + da * da + db * db).squareRoot() * 100
    }

    public static func closest(to target: RGBColor, in palette: [PaletteColor]) throws -> PaletteColor {
        try PaletteMatcher(palette: palette).closest(to: target)
    }

    private static func linear(_ channel: UInt8) -> Double {
        let value = Double(channel) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func convert(_ rgb: RGBColor) -> OKLab {
        let red = linear(rgb.red)
        let green = linear(rgb.green)
        let blue = linear(rgb.blue)
        let l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
        let m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
        let s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)
        return OKLab(
            l: 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            a: 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            b: 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        )
    }
}

struct PaletteMatcher: Sendable {
    private let entries: [(color: PaletteColor, lab: OKLab)]

    init(palette: [PaletteColor]) throws {
        guard !palette.isEmpty else { throw PatternCoreError.emptyPalette }
        entries = palette.map { ($0, ColorDistance.convert($0.rgb)) }
    }

    func closest(to target: RGBColor) throws -> PaletteColor {
        guard var closest = entries.first else { throw PatternCoreError.emptyPalette }
        let targetLab = ColorDistance.convert(target)
        var minimum = Double.infinity
        for candidate in entries {
            let dl = targetLab.l - candidate.lab.l
            let da = targetLab.a - candidate.lab.a
            let db = targetLab.b - candidate.lab.b
            let distance = (dl * dl + da * da + db * db).squareRoot() * 100
            if distance < minimum {
                minimum = distance
                closest = candidate
                if distance == 0 { break }
            }
        }
        return closest.color
    }
}
