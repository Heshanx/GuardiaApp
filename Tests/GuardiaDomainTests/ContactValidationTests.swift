import Testing
@testable import GuardiaDomain

@Test(arguments: ["", "   ", "\n"])
func rejectsEmptyContactName(name: String) {
    #expect(!ContactValidation.isValid(name: name, phone: "0772345678"))
}

@Test(arguments: ["", "abc", "123456", "1234567890123456"])
func rejectsInvalidPhoneLength(phone: String) {
    #expect(!ContactValidation.isValid(name: "Amma", phone: phone))
}

@Test func acceptsFormattedInternationalNumber() {
    #expect(ContactValidation.isValid(name: "Amma", phone: "+94 77 234 5678"))
}

@Test(arguments: ["450abc", "0", "-20", "nan", "inf", "450.123", "1,000", ""])
func rejectsInvalidFare(text: String) {
    #expect(FareValidation.parse(text) == nil)
}

@Test func acceptsLocaleDecimalFare() {
    #expect(FareValidation.parse("450,50", decimalSeparator: ",") == 450.5)
    #expect(FareValidation.parse(" 450.50 ") == 450.5)
}
