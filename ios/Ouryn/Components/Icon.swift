import SwiftUI

// @expo/vector-icons 의 Ionicons 를 그대로 사용 (같은 글꼴 + 같은 글리프 표)

enum Ionicons {
    static let map: [String: Int] = {
        guard let url = Bundle.main.url(forResource: "Ionicons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else { return [:] }
        return obj
    }()

    static func glyph(_ name: String) -> String {
        guard let code = map[name], let scalar = UnicodeScalar(code) else { return "" }
        return String(Character(scalar))
    }
}

struct Icon: View {
    let name: String
    var size: CGFloat = 20
    var color: Color = C.text

    init(_ name: String, _ size: CGFloat = 20, _ color: Color = C.text) {
        self.name = name
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(Ionicons.glyph(name))
            .font(.custom("Ionicons", fixedSize: size))
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize()
            .frame(width: size, height: size)
    }
}
