struct DisplayPreset: Equatable {
    let name: String
    let menuTitle: String
    let footnote: String
    let pixelWidth: Int
    let pixelHeight: Int
    let hiDPI: Bool

    var pointSize: (width: Int, height: Int) {
        hiDPI ? (pixelWidth / 2, pixelHeight / 2) : (pixelWidth, pixelHeight)
    }

    init(name: String, menuTitle: String = "", footnote: String = "",
         pixelWidth: Int, pixelHeight: Int, hiDPI: Bool) {
        self.name = name
        self.menuTitle = menuTitle
        self.footnote = footnote
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hiDPI = hiDPI
    }

    static let all: [DisplayPreset] = [
        DisplayPreset(name: "Best (2960×1848 HiDPI)", menuTitle: "Sharp",
                      footnote: "2960×1848 HiDPI", pixelWidth: 2960, pixelHeight: 1848, hiDPI: true),
        DisplayPreset(name: "Balanced (2560×1600 HiDPI)", menuTitle: "Balanced",
                      footnote: "2560×1600 HiDPI", pixelWidth: 2560, pixelHeight: 1600, hiDPI: true),
        DisplayPreset(name: "Compatibility (1480×924 1×)", menuTitle: "Compatible",
                      footnote: "1480×924 1×", pixelWidth: 1480, pixelHeight: 924, hiDPI: false),
    ]
    static let `default` = all[0]
}
