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
    @AppStorage(SettingsKeys.doctorQuestions) private var questions = ""
    /// Abgewählte Teile, durch Komma getrennt (leer = alles drin).
    @AppStorage("tagwerk.report.excludedSections") private var excludedRaw = ""
    @State private var weeks = 8
    @State private var name = ""
    @State private var loaded = false
    @State private var file: ReportFile?
    @State private var failed = false

    struct ReportFile: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
    }

    private var sections: Set<ReportSection> {
        let excluded = Set(excludedRaw.split(separator: ",").compactMap { ReportSection(rawValue: String($0)) })
        return Set(ReportSection.allCases).subtracting(excluded)
    }

    private func binding(_ section: ReportSection) -> Binding<Bool> {
        Binding(
            get: { sections.contains(section) },
            set: { isOn in
                var excluded = Set(ReportSection.allCases).subtracting(sections)
                if isOn { excluded.remove(section) } else { excluded.insert(section) }
                excludedRaw = ReportSection.allCases.filter(excluded.contains).map(\.rawValue).joined(separator: ",")
            }
        )
    }

    var body: some View {
        let calendar = AppModel.calendar
        let report = makeReport(calendar: calendar)
        let completeness = report.completeness
        Form {
            Section {
                Picker("Zeitraum", selection: $weeks) {
                    Text("2 Wochen").tag(2)
                    Text("4 Wochen").tag(4)
                    Text("8 Wochen").tag(8)
                    Text("3 Monate").tag(13)
                    Text("6 Monate").tag(26)
                }
                LabeledField(title: "Name im Bericht (optional)", text: $name, prompt: "z. B. Vor- und Nachname")
            } footer: {
                Text(report.periodLabel(calendar: calendar))
            }

            Section {
                HStack(spacing: Spacing.s) {
                    ProgressRing(fraction: completeness.fraction, tint: completeness.fraction >= 0.8 ? .green : .orange, lineWidth: 7) {
                        Text("\(Int((completeness.fraction * 100).rounded())) %")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                    .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(completeness.summary)
                            .font(.subheadline.weight(.semibold))
                        Text("Essen an \(completeness.withMeals), Beschwerden an \(completeness.withSymptomInfo), Bewegung an \(completeness.withActivityInfo) Tagen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Vollständigkeit")
            } footer: {
                Text("Ein Tag ist vollständig mit Essen und Beschwerden. Tippe an guten Tagen „Keine Beschwerden“, damit der Arzt sieht, dass nichts war.")
            }

            Section {
                ForEach(ReportSection.allCases) { section in
                    Toggle(isOn: binding(section)) {
                        LabeledContent(section.title, value: value(for: section, report: report, calendar: calendar))
                    }
                    .accessibilityIdentifier("report.section.\(section.rawValue)")
                }
            } header: {
                Text("Inhalt")
            }

            Section {
                TextField("z. B. Kann das Histamin sein? Soll ich DAO weiter nehmen?", text: $questions, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("report.questions")
            } header: {
                Text("Fragen an den Arzt")
            } footer: {
                Text("Stehen auf der ersten Seite. Bleiben gespeichert, bis du sie löschst.")
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

    private func value(for section: ReportSection, report: DoctorReport, calendar: Calendar) -> String {
        switch section {
        case .medications: return "\(report.medications.count)"
        case .symptoms: return report.symptomLog.isEmpty ? "keine" : "\(report.symptomLog.count) an \(report.symptomDayCount(calendar: calendar)) T."
        case .pain: return report.painSummary.count == 0 ? "keine" : "\(report.painSummary.count) an \(report.painSummary.days) T."
        case .nutrition: return "\(report.mealCount) Mahlz."
        case .activity: return report.activities.isEmpty ? "keine" : "\(report.activities.count) Einheiten"
        case .wellbeing: return "\(report.checkIns.days) Check-ins"
        case .weight: return report.weights.isEmpty ? "–" : "\(report.weights.count) Werte"
        case .diary: return "\(report.diary.count) Tage"
        case .log: return "\(report.symptomLog.count + report.pains.count)"
        }
    }

    private func makeReport(calendar: Calendar) -> DoctorReport {
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: today) ?? today
        return InsightsActions.doctorReport(
            from: from, to: now, name: name.trimmingCharacters(in: .whitespaces), questions: questions, now: now, calendar: calendar, in: context
        )
    }

    private func build(_ report: DoctorReport, calendar: Calendar) {
        if let url = DoctorReportPDF.render(report, sections: sections, calendar: calendar) {
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

    static func render(_ report: DoctorReport, sections: Set<ReportSection> = Set(ReportSection.allCases), calendar: Calendar) -> URL? {
        let pages = DoctorReportPages.make(report, sections: sections, calendar: calendar)
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
    static let diaryLinesPerPage = 62

    static func make(_ report: DoctorReport, sections: Set<ReportSection> = Set(ReportSection.allCases), calendar: Calendar) -> [AnyView] {
        var pages: [AnyView] = [AnyView(ReportFirstPage(report: report, sections: sections, calendar: calendar))]
        let showsPainPage = sections.contains(.pain) && !report.pains.isEmpty
        if sections.contains(.symptoms) || sections.contains(.activity) || (sections.contains(.pain) && report.pains.isEmpty) {
            pages.append(AnyView(ReportSymptomsActivityPage(report: report, sections: sections, calendar: calendar)))
        }
        if showsPainPage {
            pages.append(AnyView(ReportPainPage(report: report, calendar: calendar)))
        }
        if !sections.isDisjoint(with: [.nutrition, .wellbeing, .weight]) {
            pages.append(AnyView(ReportSecondPage(report: report, sections: sections, calendar: calendar)))
        }
        if sections.contains(.diary) {
            let chunks = DiaryPagination.pages(report.diary, linesPerPage: diaryLinesPerPage)
            for (index, rows) in chunks.enumerated() {
                pages.append(AnyView(ReportDiaryPage(rows: rows, isFirst: index == 0, calendar: calendar)))
            }
        }
        if sections.contains(.log) {
            let rows = report.symptomLog
            var start = 0
            while start < rows.count {
                let end = min(start + logRowsPerPage, rows.count)
                pages.append(AnyView(ReportLogPage(rows: Array(rows[start..<end]), isFirst: start == 0, calendar: calendar)))
                start = end
            }
            let pains = report.pains
            start = 0
            while start < pains.count {
                let end = min(start + logRowsPerPage, pains.count)
                pages.append(AnyView(ReportPainLogPage(rows: Array(pains[start..<end]), isFirst: start == 0, calendar: calendar)))
                start = end
            }
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
    let sections: Set<ReportSection>
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

            ReportHeading("Überblick")
            Text(report.completeness.summary + ". Ein Tag zählt als vollständig mit Essen und Angaben zu Beschwerden (auch „keine“).")
                .font(ReportStyle.body)
            HStack(alignment: .top, spacing: 0) {
                overview("Beschwerden", report.symptomLog.isEmpty ? "keine" : "\(report.symptomLog.count) an \(report.symptomDayCount(calendar: calendar)) Tagen")
                overview("Schmerzen", report.painSummary.count == 0 ? "keine" : "\(report.painSummary.count)× · Ø \(CheckInAverages.format(report.painSummary.averageIntensity))/10")
                overview("Beschwerdefrei", "\(report.completeness.symptomFreeDays) Tage")
                overview("Bewegung", activityText)
                overview("Mahlzeiten", "\(report.mealCount)")
            }
            .padding(.top, 6)

            if !report.questions.isEmpty {
                ReportHeading("Fragen an den Arzt")
                Text(report.questions)
                    .font(.system(size: 10.5))
                    .lineLimit(12)
            }

            if sections.contains(.medications) {
                ReportHeading("Medikamente und Einnahmetreue")
                if report.medications.isEmpty {
                    Text("Keine Medikamente erfasst.").font(ReportStyle.body)
                } else {
                    ReportTable(columns: [("Medikament", 0.42), ("Plan", 0.33), ("Einnahme", 0.25)]) {
                        ForEach(report.medications.prefix(12)) { line in
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
                    if report.medications.count > 12 {
                        Text("… und \(report.medications.count - 12) weitere").font(ReportStyle.small).foregroundStyle(ReportStyle.muted)
                    }
                    Text("Einnahmen mit Uhrzeit stehen in der Tag-für-Tag-Tabelle.")
                        .font(ReportStyle.small)
                        .foregroundStyle(ReportStyle.muted)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var activityText: String {
        guard !report.activityWeeks.isEmpty else { return "–" }
        let average = Double(report.activityWeeks.reduce(0) { $0 + $1.minutes }) / Double(report.activityWeeks.count)
        return "Ø \(Int(average.rounded())) Min./Woche"
    }

    private func overview(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(ReportStyle.small).foregroundStyle(ReportStyle.muted)
            Text(value).font(.system(size: 10, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Beschwerden (Verlauf, Arten) und Bewegung (Minuten je Woche, Arten).
private struct ReportSymptomsActivityPage: View {
    let report: DoctorReport
    let sections: Set<ReportSection>
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sections.contains(.symptoms) {
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
                    .frame(height: 100)
                    .padding(.vertical, 8)
                    ReportTable(columns: [("Beschwerde", 0.5), ("Anzahl", 0.25), ("Ø Stärke", 0.25)]) {
                        ForEach(report.symptomTypes.prefix(8)) { line in
                            ReportRow(widths: [0.5, 0.25, 0.25]) {
                                Text(line.type.title)
                                Text("\(line.count)")
                                Text(CheckInAverages.format(line.averageSeverity))
                            }
                        }
                    }
                }
            }

            if sections.contains(.pain) && report.pains.isEmpty {
                ReportHeading("Schmerzen")
                Text("Im Zeitraum keine Schmerzen eingetragen.").font(ReportStyle.body)
            }

            if sections.contains(.activity) {
                ReportHeading("Bewegung und Sport")
                if report.activities.isEmpty {
                    Text("Im Zeitraum keine Bewegung und kein Training eingetragen.").font(ReportStyle.body)
                } else {
                    Text("\(report.activities.count) Einheiten, davon \(report.activities.filter { $0.kind == .gym }.count) im Gym. Balken: Minuten je Woche, Linie: 150 Minuten (WHO-Empfehlung für mittlere Bewegung).")
                        .font(ReportStyle.body)
                    Chart {
                        ForEach(report.activityWeeks) { week in
                            BarMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Minuten", week.minutes))
                                .foregroundStyle(Color.green.opacity(0.7))
                        }
                        RuleMark(y: .value("Ziel", ActivityStats.weeklyTarget))
                            .foregroundStyle(ReportStyle.muted)
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: max(1, report.activityWeeks.count / 8))) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .font(ReportStyle.small)
                    .frame(height: 100)
                    .padding(.vertical, 8)
                    ReportTable(columns: [("Art", 0.5), ("Einheiten", 0.25), ("Minuten", 0.25)]) {
                        ForEach(report.activityKinds.prefix(8)) { line in
                            ReportRow(widths: [0.5, 0.25, 0.25]) {
                                Text(line.kind.title)
                                Text("\(line.sessions)")
                                Text("\(line.minutes)")
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Schmerzen: Körperkarte, Orte, Verlauf, Art, Auslöser, was geholfen hat.
private struct ReportPainPage: View {
    let report: DoctorReport
    let calendar: Calendar

    var body: some View {
        let summary = report.painSummary
        let counts = Dictionary(summary.regions.map { ($0.region, $0.count) }, uniquingKeysWith: { lhs, _ in lhs })
        VStack(alignment: .leading, spacing: 0) {
            ReportHeading("Schmerzen")
            Text("\(summary.count) Einträge an \(summary.days) Tagen. Stärke 0–10 (NRS): Ø \(CheckInAverages.format(summary.averageIntensity)), höchstens \(summary.maxIntensity ?? 0). \(summary.afterActivity) davon am Tag eines Trainings oder am Tag danach.")
                .font(ReportStyle.body)
            HStack(alignment: .top, spacing: 18) {
                BodyHeatMap(counts: counts)
                    .frame(width: 190, height: 180)
                ReportTable(columns: [("Ort", 0.5), ("Anzahl", 0.17), ("Ø", 0.16), ("max.", 0.17)]) {
                    ForEach(summary.regions.prefix(10)) { line in
                        ReportRow(widths: [0.5, 0.17, 0.16, 0.17]) {
                            Text(line.region.title)
                            Text("\(line.count)")
                            Text(CheckInAverages.format(line.averageIntensity))
                            Text("\(line.maxIntensity)")
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            Chart(summary.weeks) { week in
                if let average = week.averageIntensity {
                    BarMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Ø Stärke", average))
                        .foregroundStyle(Color.red.opacity(0.6))
                }
                if let maximum = week.maxIntensity {
                    PointMark(x: .value("Woche", week.weekStart, unit: .weekOfYear), y: .value("Höchste", maximum))
                        .foregroundStyle(Color.red)
                        .symbolSize(16)
                }
            }
            .chartYScale(domain: 0...10)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: max(1, summary.weeks.count / 8))) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 5, 10])
            }
            .font(ReportStyle.small)
            .frame(height: 90)
            Text("Balken: durchschnittliche Stärke je Woche, Punkt: höchster Wert.")
                .font(ReportStyle.small)
                .foregroundStyle(ReportStyle.muted)
                .padding(.top, 2)
            if !summary.qualities.isEmpty {
                labeled("Art", summary.qualities.map { "\($0.0.title) \($0.1)×" }.joined(separator: ", "))
            }
            if !summary.triggers.isEmpty {
                labeled("Vermuteter Auslöser", summary.triggers.map { "\($0.0.title) \($0.1)×" }.joined(separator: ", "))
            }
            if !summary.reliefs.isEmpty {
                labeled("Geholfen hat", summary.reliefs.map { "\($0.0.title) \($0.1)×" }.joined(separator: ", "))
            }
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        Text("\(Text(label + ":").fontWeight(.semibold)) \(value)")
            .font(ReportStyle.body)
            .padding(.top, 6)
    }
}

private struct ReportSecondPage: View {
    let report: DoctorReport
    let sections: Set<ReportSection>
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sections.contains(.nutrition) {
                nutrition
            }
            if sections.contains(.wellbeing) {
                wellbeing
            }
            if sections.contains(.weight) {
                weight
            }
        }
    }

    @ViewBuilder
    private var nutrition: some View {
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

    }

    @ViewBuilder
    private var wellbeing: some View {
            if report.checkIns.days > 0 {
                ReportHeading("Befinden und Schlaf (tägliche Check-ins)")
                Text("\(report.checkIns.days) Tage mit Check-in. Skala 1–5, bei Stress ist niedrig gut." + (report.averageSleepHours.map { " Schlafdauer Ø \(WeightFormat.number(($0 * 10).rounded() / 10)) Std." } ?? ""))
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

    }

    @ViewBuilder
    private var weight: some View {
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

/// Tag-für-Tag-Tabelle: Essen, Beschwerden und Schmerzen, Medikamente, Bewegung, Befinden.
private struct ReportDiaryPage: View {
    let rows: [DiaryRow]
    let isFirst: Bool
    let calendar: Calendar

    static let widths: [CGFloat] = [0.1, 0.29, 0.25, 0.13, 0.12, 0.11]
    static let tiny = Font.system(size: 7.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportHeading(isFirst ? "Tagebuch Tag für Tag" : "Tagebuch Tag für Tag (Fortsetzung)")
            if isFirst {
                Text("Uhrzeit vor jedem Eintrag. Beschwerden Stärke 1–5, Schmerzen 0–10. „keine“ = ausdrücklich beschwerdefrei. Leere Zeilen = nichts eingetragen.")
                    .font(ReportStyle.small)
                    .foregroundStyle(ReportStyle.muted)
                    .padding(.bottom, 4)
            }
            ColumnsLayout(widths: Self.widths) {
                ForEach(["Tag", "Essen", "Beschwerden, Schmerzen", "Medikamente", "Bewegung", "Befinden"], id: \.self) { title in
                    Text(title)
                }
            }
            .font(ReportStyle.small.weight(.semibold))
            .foregroundStyle(ReportStyle.muted)
            .padding(.vertical, 2)
            Rectangle().fill(ReportStyle.line).frame(height: 0.5)
            ForEach(rows) { row in
                ColumnsLayout(widths: Self.widths) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.day.formatted(.dateTime.weekday(.abbreviated)))
                        Text(row.day.formatted(.dateTime.day(.twoDigits).month(.twoDigits)))
                            .fontWeight(.semibold)
                    }
                    cell(row.meals, empty: "–")
                    cell(row.complaints, empty: "", highlight: true)
                    cell(row.medications, empty: "")
                    cell(row.activities, empty: "")
                    cell(row.wellbeing.map { [$0] } ?? [], empty: "")
                }
                .font(Self.tiny)
                .padding(.vertical, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(ReportStyle.line.opacity(0.6)).frame(height: 0.5)
                }
            }
        }
    }

    private func cell(_ items: [String], empty: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if items.isEmpty {
                Text(empty).foregroundStyle(ReportStyle.muted)
            }
            ForEach(items.indices, id: \.self) { index in
                Text(items[index])
                    .lineLimit(3)
                    .foregroundStyle(highlight && items[index] != "keine" ? ReportStyle.accent : ReportStyle.ink)
            }
        }
    }
}

/// Alle Schmerz-Einträge mit Ort, Stärke, Art, Dauer, Auslöser und Linderung.
private struct ReportPainLogPage: View {
    let rows: [PainFact]
    let isFirst: Bool
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReportHeading(isFirst ? "Schmerz-Protokoll" : "Schmerz-Protokoll (Fortsetzung)")
            ReportTable(columns: [("Datum", 0.16), ("Ort", 0.24), ("Stärke", 0.08), ("Art, Dauer", 0.2), ("Auslöser, geholfen", 0.32)]) {
                ForEach(rows) { fact in
                    ReportRow(widths: [0.16, 0.24, 0.08, 0.2, 0.32]) {
                        Text(fact.date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute()))
                        Text(fact.regionText)
                        Text("\(fact.intensity)/10")
                        Text(kind(fact))
                        Text(details(fact))
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private func kind(_ fact: PainFact) -> String {
        var parts: [String] = []
        if !fact.qualities.isEmpty { parts.append(fact.qualities.map(\.title).joined(separator: ", ")) }
        if let minutes = fact.durationMinutes { parts.append(DurationText.short(minutes)) }
        return parts.joined(separator: " · ")
    }

    private func details(_ fact: PainFact) -> String {
        var parts: [String] = []
        if !fact.triggers.isEmpty { parts.append(fact.triggers.map(\.title).joined(separator: ", ")) }
        if !fact.reliefs.isEmpty { parts.append("geholfen: " + fact.reliefs.map(\.title).joined(separator: ", ")) }
        if !fact.note.isEmpty { parts.append(fact.note) }
        return parts.joined(separator: " · ")
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
