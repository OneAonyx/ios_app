import Foundation
import Testing
@testable import TagwerkCore

@Suite("Geld: bekommen und zahlen")
struct MoneyBookTests {
    let now = date(2026, 11, 9, 12)

    @Test func paymentsSumsAndOrder() {
        var book = MoneyBook()
        let lena = MoneyEntry(direction: .incoming, kind: .personal, counterparty: "Lena", title: "Konzertkarten", cents: 4_500, date: date(2026, 11, 1))
        let invoice = MoneyEntry(direction: .incoming, kind: .invoice, counterparty: "Muster GmbH", title: "Rechnung 14", cents: 120_000, date: date(2026, 10, 1), dueDate: date(2026, 11, 1))
        let rent = MoneyEntry(direction: .outgoing, kind: .invoice, counterparty: "Stadtwerke", cents: 8_990, date: date(2026, 11, 5), dueDate: date(2026, 11, 20))
        let tom = MoneyEntry(direction: .outgoing, kind: .personal, counterparty: "Lena", title: "Pizza", cents: 1_200, date: date(2026, 11, 8))
        [lena, invoice, rent, tom].forEach { book.upsert($0) }

        #expect(book.openCents(.incoming) == 124_500)
        #expect(book.openCents(.outgoing) == 10_190)
        #expect(book.open(.incoming, now: now, calendar: berlin).first?.id == invoice.id, "Überfällig zuerst")
        #expect(book.overdue(now: now, calendar: berlin).map(\.id) == [invoice.id])
        #expect(invoice.dueText(now: now, calendar: berlin) == "seit 8 Tagen überfällig")
        #expect(rent.dueText(now: now, calendar: berlin) == "fällig in 11 Tagen")

        book.addPayment(to: lena.id, cents: 2_000, date: now)
        #expect(book.entries.first { $0.id == lena.id }?.openCents == 2_500)
        book.addPayment(to: lena.id, cents: 9_999, date: now)
        #expect(book.entries.first { $0.id == lena.id }?.isSettled == true, "Höchstens der offene Betrag")
        #expect(book.settled.map(\.id) == [lena.id])

        // Lena: bekommt nichts mehr, ich schulde ihr 12 €.
        #expect(book.balances.first { $0.name == "Lena" }?.cents == -1_200)
        book.settle(id: invoice.id, date: now)
        #expect(book.overdue(now: now, calendar: berlin).isEmpty)
        book.reopen(id: invoice.id)
        #expect(book.entries.first { $0.id == invoice.id }?.openCents == 120_000)
        #expect(book.knownCounterparties.first == "Lena")
    }

    @Test func amountsAndTexts() {
        #expect(MoneyBook.cents(from: "12,50") == 1_250)
        #expect(MoneyBook.cents(from: "12.5") == 1_250)
        #expect(MoneyBook.cents(from: "1.250,00 €") == 125_000)
        #expect(MoneyBook.cents(from: "abc") == nil)
        #expect(MoneyBook.cents(from: "") == nil)
        #expect(MoneyBook.euro(125_000) == "1.250,00 €")
        #expect(MoneyBook.euro(5) == "0,05 €")

        let lena = MoneyEntry(direction: .incoming, kind: .personal, counterparty: "Lena Berg", title: "Konzertkarten", cents: 4_500, date: date(2026, 11, 1))
        #expect(MoneyBook.reminderText(for: lena, now: now, calendar: berlin) == "Hi Lena, kleine Erinnerung an die 45,00 € für Konzertkarten vom 1. Nov. – danke dir!")
        let invoice = MoneyEntry(direction: .incoming, kind: .invoice, counterparty: "Muster GmbH", title: "Rechnung 14", cents: 120_000, date: date(2026, 10, 1), dueDate: date(2026, 11, 1))
        #expect(MoneyBook.reminderText(for: invoice, now: now, calendar: berlin).contains("1.200,00 €"))
    }

    @Test func storageRoundTrip() {
        var book = MoneyBook()
        book.upsert(MoneyEntry(direction: .outgoing, kind: .invoice, counterparty: "Telekom", cents: 3_999, date: date(2026, 11, 1), dueDate: date(2026, 11, 15)))
        book.addPayment(to: book.entries[0].id, cents: 1_000, date: date(2026, 11, 2))
        #expect(MoneyBook.decode(MoneyBook.encode(book)) == book)
        #expect(MoneyBook.decode("").entries.isEmpty)
    }
}
