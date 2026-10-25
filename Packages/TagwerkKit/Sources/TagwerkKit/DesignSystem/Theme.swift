import SwiftUI

/// Abstände im 4-pt-Raster.
public enum Spacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
}

/// Eckenradien, immer mit `style: .continuous` verwenden.
public enum Radius {
    public static let card: CGFloat = 22
    public static let control: CGFloat = 14
    public static let chip: CGFloat = 10
}

/// Mindestgrößen für Tippflächen. Im Gym-Modus größer (eine Hand, verschwitzte Finger).
public enum TouchTarget {
    public static let standard: CGFloat = 44
    public static let gym: CGFloat = 56
}

public extension Color {
    /// Hintergrund für Inhaltskarten (keine Glas-Optik, damit Inhalte ruhig und lesbar bleiben).
    static let tagwerkCard = Color(uiColor: .secondarySystemGroupedBackground)
    /// Seitenhintergrund hinter den Karten.
    static let tagwerkPage = Color(uiColor: .systemGroupedBackground)

    static let tagwerkCoral = Color(red: 1.0, green: 0.42, blue: 0.36)
    static let tagwerkSun = Color(red: 1.0, green: 0.62, blue: 0.04)
}

/// Akzentfarben je Bereich. Nur als Akzent nutzen, nie als große Fläche.
public enum ModuleAccent {
    public static let tasks = Color.indigo
    public static let calendar = Color.blue
    public static let medication = Color.mint
    public static let training = Color.tagwerkCoral
    public static let nutrition = Color.orange
    public static let health = Color.pink
    public static let sleep = Color.purple
    public static let today = Color.tagwerkSun
}
