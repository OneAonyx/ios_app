import Charts
import PDFKit
import SwiftData
import SwiftUI
import TagwerkCore
import TagwerkKit

/// Arztbericht: Zeitraum wählen, Inhalt prüfen, PDF erstellen und teilen.
struct DoctorReportView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.userName) private var userName = ""
    @State private var weeks = 8
    @State private var name = ""
    @State private var loaded = false
    @State private var file: ReportFile?
    @State private var failed = false

    struct ReportFile: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        let calendar = AppModel.calendar
        let report = makeReport(calendar: calendar)
        Form {
            Section {
                Picker("Zeitraum", selection: $weeks) {
                    Text("4 Wochen").tag(4)
                    Text("8 Wochen").tag(8)
                    Text("3 Monate").tag(13)
                    Text("6 Monate").tag(26)
                }
                LabeledField(title: "Name im Bericht (optional)", text: $name, prompt: "z. B. Vor- und Nachname")
            } footer: {
                Text(report.periodLabel(calendar: calendar))
            }

            Section("Inhalt") {
                LabeledContent("Medikamente", value: "\(report.medications.count)")
                LabeledContent("Beschwerden", value: report.symptomLog.isEmpty ? "keine" : "\(report.symptomLog.count) an \(report.symptomDayCount(calendar: calendar)) Tagen")
                LabeledContent("Mahlzeiten", value: "\(report.mealCount)")
                LabeledContent("Auffällige Muster", value: "\(report.findings.count)")
                LabeledContent("Check-ins", value: "\(report.checkIns.days) Tage")
                LabeledContent("Gewicht", value: report.weightChangeText ?? "–")
            }

            Section {
                Button {
                    build(report, calendar: calendar)
                } label: {
                    Label("PDF erstellen", systemImage: "doc.richtext")
                        .font(.headline)
                }
                .accessibilityIdentifier("report.build")
                if failed {
                    Label("Das PDF ließ sich nicht erstellen.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Selbst erfasste Daten, keine Diagnose. Das PDF entsteht auf deinem iPhone und wird nur geteilt, wenn du es selbst weitergibst.")
            }
        }
        .navigationTitle("Arztbericht")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $file) { file in
            DoctorReportPreview(url: file.url)
        }
        .onAppear {
            guard !loaded else { return }
            name = userName
            loaded = true
        }
    }

    private func makeReport(calendar: Calendar) -> DoctorReport {
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today
        return InsightsActions.doctorReport(
            from: from, to: now, name: name.trimmingCharacters(in: .whitespaces), now: now, calendar: calendar, in: context
        )
    }

    private func build(_ report: DoctorReport, calendar: Calendar) {
        if let url = DoctorReportPDF.render(report, calendar: calendar) {
            failed = false
            file = ReportFile(url: url)
        } else {
            failed = true
        }
    }
}

/// Fertiges PDF ansehen und teilen.
struct DoctorReportPreview: View {
    let url: URL

    var body: some View {
        PDFPreview(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Vorschau")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Label("Teilen", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("report.share")
                }
            }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

// MARK: - PDF

/// Schreibt den Bericht als A4-PDF in den temporären Ordner.
@MainActor
enum DoctorReportPDF {
    static let pageSize = CGSize(width: 595, height: 842)

    static func render(_ report: DoctorReport, calendar: Calendar) -> URL? {
        let pages = DoctorReportPages.make(report, calendar: calendar)
        let stamp = report.createdAt.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit-Bericht-\(stamp).pdf")
        try? FileManager.default.removeItem(at: url)
        var box = CGRect(origin: .zero, size: pageSize)
        let info = [kCGPDFContextTitle as String: "Gesundheitsbericht", kCGPDFContextCreator as String: "Orbit"] as CFDictionary
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, info) else { return nil }
        for index in pages.indices {
            let page = ReportPageFrame(number: index + 1, total: pages.count, createdAt: report.createdAt) {
                pages[index]
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }
}

/// Seiteninhalte. Lange Listen werden gekürzt bzw. auf Folgeseiten verteilt.
@MainActor
enum DoctorReportPages {
    static let logRowsPerPage = 30

    static func make(_ report: DoctorReport, calendar: Calendar) -> [AnyView] {
        var pages: [AnyView] = [
            AnyView(ReportFirstPage(report: report, calendar: calendar)),
            AnyView(ReportSecondPage(report: report, calendar: calendar)),
        ]
        let rows = report.symptomLog
        var start = 0
        while start < rows.count {
            let end = min(start + logRowsPerPage, rows.count)
            pages.append(AnyView(ReportLogPage(rows: Array(rows[start..<end]), isFirst: start == 0, calendar: calendar)))
            start = end
        }
        return pages
    }
}

private enum ReportStyle {
    static let ink = Color.black
    static let muted = Color(white: 0.4)
    static let line = Color(white: 0.85)
    static let accent = Color(red: 0.75, green: 0.15, blue: 0.4)
    static let body = Font.system(size: 10)
    static let small = Font.system(size: 8.5)
    static let heading = Font.system(size: 13, weight: .semibold)
}

private struct ReportPageFrame<Content: View>: View {
    let number: Int
    let total: Int
    let createdAt: Date
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 0)
            Rectangle().fill(ReportStyle.line).frame(height: 0.5)
            HStack {
                Text("Selbst erfasste Daten aus der App Orbit · keine Diagnose")
                Spacer()
                Text("Seite \(number) von \(total)")
            }
            .font(ReportStyle.small)
            .foregroundStyle(ReportStyle.muted)
            .padding(.top, 6)
        }
        .foregroundStyle(ReportStyle.ink)
        .padding(.horizontal, 44)
        .padding(.top, 44)
        .padding(.bottom, 30)
        .background(Color.white)
    }
}

private struct ReportHeading: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(ReportStyle.heading)
                .foregroundStyle(ReportStyle.accent)
            Rectangle().fill(ReportStyle.accent.opacity(0.4)).frame(height: 1)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

private struct ReportFirstPage: View {
    let report: DoctorReport
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gesundheitsbericht")
                .font(.system(size: 22, weight: .bold))
            if !report.name.isEmpty {
                Text(report.name)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.top, 2)
            }
            Text("Zeitraum: \(report.periodLabel(calendar: calendar)) · erstellt am \(report.createdAt.formatted(.dateTime.day().month(.twoDigits).year()))")
                .font(ReportStyle.body)
                .foregroundStyle(ReportStyle.muted)
                .padding(.top, 4)

            ReportHeading("Medikamente und Einnahmetreue")
            if report.medications.isEmpty {
                Text("Keine Medikamente erfasst.").font(ReportStyle.body)
            } else {
                ReportTable(columns: [("Medikament", 0.42), ("Plan", 0.33), ("Einnahme", 0.25)]) {
                    ForEach(report.medications.prefix(14)) { line in
                        ReportRow(widths: [0.42, 0.33, 0.25]) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(line.name + (line.isActive ? "" : " (beendet)"))
                                    .fontWeight(.medium)
                                if let hint = line.hint {
                                    Text(hint).font(ReportStyle.small).foregroundStyle(ReportStyle.muted)
                                }
                            }
                            Text(line.schedule)
                            Text(line.adherenceText + (line.adherence != nil && line.extraIntakes > 0 ? ", +\(line.extraIntakes) extra" : ""))
                        }
                    }
                }
                if report.medications.count > 14 {
                    Text("… und \(report.medications.count - 14) weitere").font(ReportStyle.small).foregroundStyle(ReportStyle.muted)
                }
            }

            ReportHeading("Beschwerden")
            if report.symptomLog.isEmpty {
                Text("Im Zeitraum keine Beschwerden eingetragen.").font(ReportStyle.body)
            } else {
                Text("\(report.symptomLog.count) Einträge an \(report.symptomDayCount(calendar: calendar)) Tagen. Stärke 1 (leicht) bis 5 (sehr stark).")
                    .font(ReportStyle.body)
                Chart(report.symptomWeeks) { week in
                    BarMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Anzahl", week.count))
                        .foregroundStyle(ReportStyle.accent.opacity(0.75))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: max(1, report.symptomWeeks.count / 8))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .font(ReportStyle.small)
                .frame(height: 110)
                .padding(.vertical, 8)
                ReportTable(columns: [("Beschwerde", 0.5), ("Anzahl", 0.25), ("Ø Stärke", 0.25)]) {
                    ForEach(report.symptomTypes.prefix(10)) { line in
                        ReportRow(widths: [0.5, 0.25, 0.25]) {
                            Text(line.type.title)
                            Text("\(line.count)")
                            Text(CheckInAverages.format(line.averageSeverity))
                        }
                    }
                }
            }
        }
    }
}

private struct ReportSecondPage: View {
    let report: DoctorReport
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportHeading("Ernährung und mögliche Auslöser (Histamin)")
            Text(nutritionSummary)
                .font(ReportStyle.body)
            if report.findings.isEmpty {
                Text("Keine auffälligen Muster gefunden (oder noch zu wenig Einträge).")
                    .font(ReportStyle.body)
                    .foregroundStyle(ReportStyle.muted)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(report.findings.prefix(8)) { finding in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(finding.name): \(finding.sentence)")
                                .font(ReportStyle.body.weight(.medium))
                            Text(finding.comparison + (finding.companionText.map { " · \($0)" } ?? ""))
                                .font(ReportStyle.small)
                                .foregroundStyle(ReportStyle.muted)
                        }
                    }
                }
                .padding(.top, 6)
                Text("Gezählt werden Beschwerden bis 24 Stunden nach dem Essen. Ein Muster ist ein Hinweis, kein Nachweis.")
                    .font(ReportStyle.small)
                    .foregroundStyle(ReportStyle.muted)
                    .padding(.top, 4)
            }
            if !report.avoidedFoods.isEmpty {
                labeled("Meide ich", report.avoidedFoods.joined(separator: ", "))
            }
            if !report.cautionFoods.isEmpty {
                labeled("Nur wenig", report.cautionFoods.joined(separator: ", "))
            }

            if report.checkIns.days > 0 {
                ReportHeading("Befinden (tägliche Check-ins)")
                Text("\(report.checkIns.days) Tage mit Check-in. Skala 1–5, bei Stress ist niedrig gut.")
                    .font(ReportStyle.body)
                HStack(spacing: 18) {
                    ForEach(CheckInScale.allCases) { scale in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(scale.title).font(ReportStyle.small).foregroundStyle(ReportStyle.muted)
                            Text("Ø " + CheckInAverages.format(report.checkIns.value(scale)))
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .padding(.top, 6)
            }

            if !report.weights.isEmpty {
                ReportHeading("Körpergewicht")
                if let text = report.weightChangeText {
                    Text(text).font(ReportStyle.body)
                }
                if report.weights.count >= 2 {
                    Chart(report.weights) { point in
                        LineMark(x: .value("Datum", point.date), y: .value("kg", point.value))
                            .foregroundStyle(ReportStyle.accent)
                        PointMark(x: .value("Datum", point.date), y: .value("kg", point.value))
                            .foregroundStyle(ReportStyle.accent)
                            .symbolSize(14)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .font(ReportStyle.small)
                    .frame(height: 100)
                    .padding(.top, 8)
                }
            }
        }
    }

    private var nutritionSummary: String {
        var parts = ["\(report.mealCount) Mahlzeiten erfasst"]
        if report.loadDays > 0 {
            parts.append("Histamin-Tageslast an \(report.elevatedLoadDays) von \(report.loadDays) Tagen erhöht oder hoch")
        }
        return parts.joined(separator: ". ") + "."
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        Text("\(Text(label + ":").fontWeight(.semibold)) \(value)")
            .font(ReportStyle.body)
            .padding(.top, 6)
    }
}

private struct ReportLogPage: View {
    let rows: [DoctorReport.SymptomLogRow]
    let isFirst: Bool
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportHeading(isFirst ? "Beschwerde-Protokoll" : "Beschwerde-Protokoll (Fortsetzung)")
            ReportTable(columns: [("Datum", 0.2), ("Beschwerde", 0.24), ("Stärke", 0.1), ("Dauer", 0.12), ("Notiz", 0.34)]) {
                ForEach(rows) { row in
                    ReportRow(widths: [0.2, 0.24, 0.1, 0.12, 0.34]) {
                        Text(row.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute()))
                        Text(row.type.title)
                        Text("\(row.severity)")
                        Text(row.durationMinutes.map(Self.duration) ?? "–")
                        Text(row.note.isEmpty ? "" : row.note)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(WeightFormat.number(Double(minutes) / 60)) Std." : "\(minutes) Min."
    }
}

/// Tabelle mit Kopfzeile. Spalten als Anteil der Breite.
private struct ReportTable<Rows: View>: View {
    let columns: [(String, CGFloat)]
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportRow(widths: columns.map { $0.1 }) {
                ForEach(columns.indices, id: \.self) { index in
                    Text(columns[index].0)
                }
            }
            .font(ReportStyle.small.weight(.semibold))
            .foregroundStyle(ReportStyle.muted)
            Rectangle().fill(ReportStyle.line).frame(height: 0.5)
            rows
        }
    }
}

/// Zeile mit festen Spaltenanteilen.
private struct ReportRow<Cells: View>: View {
    let widths: [CGFloat]
    @ViewBuilder let cells: Cells

    var body: some View {
        ColumnsLayout(widths: widths) {
            cells
        }
        .font(ReportStyle.body)
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ReportStyle.line.opacity(0.6)).frame(height: 0.5)
        }
    }
}

/// Ordnet die Zellen nebeneinander an, jede mit ihrem Anteil an der Breite.
private struct ColumnsLayout: Layout {
    let widths: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? (DoctorReportPDF.pageSize.width - 88)
        var height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: total * fraction(index) - 4, height: nil))
            height = max(height, size.height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for index in subviews.indices {
            let width = bounds.width * fraction(index)
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width - 4, height: nil))
            x += width
        }
    }

    private func fraction(_ index: Int) -> CGFloat {
        index < widths.count ? widths[index] : 0.1
    }
}
