import XCTest
import Foundation
@testable import TokenBar

/// Regression coverage for the custom-site field path.
///
/// Quota units are copied verbatim out of page text, so the same currency can
/// arrive as U+00A5 (¥) or U+FFE5 (￥). Comparing raw strings against "¥" made
/// every fullwidth-yuan balance render as an empty progress bar.
final class CustomFieldCurrencyTests: XCTestCase {

    // MARK: - QuotaUnit

    func test_normalized_collapsesDifferentEncodingsOfTheSameSymbol() {
        XCTAssertEqual(QuotaUnit.normalized("￥"), "¥")
        XCTAssertEqual(QuotaUnit.normalized("＄"), "$")
        XCTAssertEqual(QuotaUnit.normalized(" ￥ "), "¥")
        XCTAssertEqual(QuotaUnit.normalized("¥"), "¥")
        XCTAssertEqual(QuotaUnit.normalized("%"), "%")
        XCTAssertEqual(QuotaUnit.normalized("credits"), "credits")
        // A code is not an encoding of a glyph, so it survives normalization.
        XCTAssertEqual(QuotaUnit.normalized("CNY"), "CNY")
    }

    func test_currencySymbol_recognizesSymbolsWordsAndIsoCodes() {
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "¥"), "¥")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "￥"), "¥")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "CNY"), "¥")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "元"), "¥")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "RMB"), "¥")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "USD"), "$")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "EUR"), "€")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "HKD"), "HKD")
        XCTAssertEqual(QuotaUnit.currencySymbol(for: "SGD"), "SGD")
    }

    func test_currencySymbol_rejectsNonMoneyUnits() {
        for unit in ["", "%", "credits", "tokens", "次", "hkd", "US"] {
            XCTAssertNil(QuotaUnit.currencySymbol(for: unit), unit)
        }
    }

    func test_displayAmount_formatsMoneyAndPlainAmounts() {
        XCTAssertEqual(QuotaUnit.displayAmount(500, unit: "￥"), "¥500.00")
        XCTAssertEqual(QuotaUnit.displayAmount(12.5, unit: "$"), "$12.50")
        XCTAssertEqual(QuotaUnit.displayAmount(1000, unit: "credits"), "1000 credits")
        XCTAssertEqual(QuotaUnit.displayAmount(1000, unit: ""), "1000")
        XCTAssertEqual(QuotaUnit.displayAmount(0.5, unit: "tokens"), "0.50 tokens")
    }

    // MARK: - Quota presentation

    func test_balanceWithFullWidthYuan_rendersAsAmountNotProgressBar() {
        let quota = Quota(id: "balance", label: "页面余额", used: 0, total: 500,
                          unit: "￥", presentation: .balance)
        XCTAssertFalse(quota.showsProgressBar)
        XCTAssertTrue(quota.isCurrency)
    }

    func test_balanceIsNotAProgressBarEvenWithoutAnExplicitHint() {
        // Built-in adapters construct balances without a presentation hint.
        let quota = Quota(id: "balance", label: "余额", used: 0, total: 500, unit: "¥")
        XCTAssertFalse(quota.showsProgressBar)
        XCTAssertTrue(quota.isCurrency)
    }

    func test_usageWindowsStillShowProgressBars() {
        let percent = Quota(id: "weekly", label: "周限额", used: 42, total: 100, unit: "%")
        XCTAssertTrue(percent.showsProgressBar)
        XCTAssertFalse(percent.isCurrency)

        // A window at 0% used must not be mistaken for a balance.
        let untouched = Quota(id: "5h", label: "5h 限额", used: 0, total: 100, unit: "%")
        XCTAssertTrue(untouched.showsProgressBar)

        let windowed = Quota(id: "credits", label: "已用额度", used: 5, total: 100,
                             unit: "credits", presentation: .usage)
        XCTAssertTrue(windowed.showsProgressBar)
    }

    func test_nonCurrencyBalanceIsNotMoneyButIsStillAnAmount() {
        let quota = Quota(id: "balance", label: "积分", used: 0, total: 1000,
                          unit: "credits", presentation: .balance)
        XCTAssertFalse(quota.showsProgressBar)
        XCTAssertFalse(quota.isCurrency)
    }

    // MARK: - CustomProviderRuntime

    func test_domBalanceRule_savedWithFullWidthYuan_rendersAmount() {
        // Exactly what the field probe saved for a site whose page renders ￥.
        let rule = CustomFieldRule(source: .dom, label: "页面余额", unit: "￥",
                                   valueKind: "balance", domSelector: "p.balance", scale: 1)
        let snapshot = CustomProviderRuntime.snapshot(providerId: "custom-1", rule: rule, text: "￥500.00")

        XCTAssertEqual(snapshot.status, .ok)
        let quota = try? XCTUnwrap(snapshot.quotas.first)
        XCTAssertEqual(quota?.unit, "¥")
        XCTAssertEqual(quota?.presentation, .balance)
        XCTAssertFalse(quota?.showsProgressBar ?? true)
        XCTAssertTrue(quota?.isCurrency ?? false)
        XCTAssertEqual(QuotaUnit.displayAmount(quota?.total ?? 0, unit: quota?.unit ?? ""), "¥500.00")
    }

    func test_percentRule_isAUsageWindow() {
        let rule = CustomFieldRule(source: .dom, label: "用量", unit: "%",
                                   valueKind: "percent", domSelector: "span", scale: 1)
        let snapshot = CustomProviderRuntime.snapshot(providerId: "custom-1", rule: rule, text: "42%")
        XCTAssertEqual(snapshot.quotas.first?.used, 42)
        XCTAssertEqual(snapshot.quotas.first?.showsProgressBar, true)
        XCTAssertEqual(snapshot.quotas.first?.presentation, .usage)
    }

    func test_usedTotalRule_needsBothNumbersAndIsAUsageWindow() {
        let rule = CustomFieldRule(source: .dom, label: "额度", unit: "",
                                   valueKind: "usedTotal", domSelector: "span", scale: 1)
        let missing = CustomProviderRuntime.snapshot(providerId: "custom-1", rule: rule, text: "已用 5")
        XCTAssertTrue(missing.quotas.isEmpty)
        guard case .error = missing.status else { return XCTFail("expected an error status") }

        let ok = CustomProviderRuntime.snapshot(providerId: "custom-1", rule: rule, text: "5 / 20")
        XCTAssertEqual(ok.quotas.first?.used, 5)
        XCTAssertEqual(ok.quotas.first?.total, 20)
        XCTAssertEqual(ok.quotas.first?.showsProgressBar, true)
    }

    func test_scaleMultipliesBalances() {
        let rule = CustomFieldRule(source: .dom, label: "余额", unit: "$",
                                   valueKind: "balance", domSelector: "span", scale: 0.01)
        let snapshot = CustomProviderRuntime.snapshot(providerId: "custom-1", rule: rule, text: "$5,000")
        XCTAssertEqual(snapshot.quotas.first?.total ?? 0, 50, accuracy: 0.0001)
    }

    func test_balanceRuleWithoutAnyNumberIsAnError() {
        let rule = CustomFieldRule(source: .dom, label: "余额", unit: "¥",
                                   valueKind: "balance", domSelector: "span", scale: 1)
        let snapshot = CustomProviderRuntime.snapshot(providerId: "custom-1", rule: rule, text: "暂无数据")
        XCTAssertTrue(snapshot.quotas.isEmpty)
        guard case .error = snapshot.status else { return XCTFail("expected an error status") }
    }

    func test_apiSnapshot_readsTheConfiguredJSONPath() {
        let rule = CustomFieldRule(source: .api, label: "接口余额", unit: "￥",
                                   valueKind: "balance", apiURL: "https://example.com/balance",
                                   apiMethod: "GET", jsonPath: "data.wallet.available", scale: 1)
        let data = Data(#"{"data":{"wallet":{"available":1234.5}}}"#.utf8)
        let snapshot = CustomProviderRuntime.apiSnapshot(providerId: "custom-1", rule: rule, data: data)
        XCTAssertEqual(snapshot.quotas.first?.total ?? 0, 1234.5, accuracy: 0.0001)
        XCTAssertFalse(snapshot.quotas.first?.showsProgressBar ?? true)
    }

    // MARK: - Definition decoding

    func test_definitionSavedBeforeTheCurrencyFix_stillDecodes() throws {
        // Shape taken from UserDefaults on a Mac that had already saved a site.
        let json = #"""
        [{"id":"custom-7dbd0d2e-d301-43ba-95cd-e6df53ae8e82","displayName":"APIKEY.FUN",
          "iconSystemName":"globe","loginURL":"https://apikey.fun/purchase",
          "rule":{"source":"dom","label":"页面余额","unit":"￥","valueKind":"balance",
                  "domSelector":"main > p:nth-of-type(3)","scale":1}}]
        """#
        let definitions = try JSONDecoder().decode([CustomProviderDefinition].self, from: Data(json.utf8))
        let definition = try XCTUnwrap(definitions.first)
        XCTAssertEqual(definition.displayName, "APIKEY.FUN")
        XCTAssertEqual(definition.rule.unit, "￥")

        // The saved unit stays fullwidth; only the derived quota is normalized.
        let text = "￥500.00"
        let snapshot = CustomProviderRuntime.snapshot(providerId: definition.id, rule: definition.rule, text: text)
        XCTAssertEqual(snapshot.quotas.first?.unit, "¥")
        XCTAssertFalse(snapshot.quotas.first?.showsProgressBar ?? true)
    }

    // MARK: - FieldCandidate → rule

    func test_fieldCandidate_ruleNormalizesUnitAndKeepsSelector() {
        let candidate = FieldCandidate(source: .dom, label: "", preview: "￥500.00", score: 90,
                                       selector: "main > p", endpoint: nil, method: nil, body: nil,
                                       jsonPath: nil, valueKind: "balance", unit: "￥")
        let rule = candidate.rule()
        XCTAssertEqual(rule.unit, "¥")
        XCTAssertEqual(rule.label, "页面余额")
        XCTAssertEqual(rule.domSelector, "main > p")
    }

    func test_fieldCandidate_ruleHonorsAnEditedLabel() {
        let candidate = FieldCandidate(source: .dom, label: "页面余额", preview: "￥500.00", score: 90,
                                       selector: "main > p", endpoint: nil, method: nil, body: nil,
                                       jsonPath: nil, valueKind: "balance", unit: "￥")
        XCTAssertEqual(candidate.rule(label: "APKEY 余额").label, "APKEY 余额")
        // A blank edit falls back to the candidate's own default.
        XCTAssertEqual(candidate.rule(label: "   ").label, "页面余额")
    }

    func test_fieldCandidate_apiRuleKeepsEndpointAndPath() {
        let candidate = FieldCandidate(source: .api, label: "available", preview: "1234.5", score: 80,
                                       selector: nil, endpoint: "https://example.com/api/wallet",
                                       method: "POST", body: #"{"a":1}"#, jsonPath: "data.available",
                                       valueKind: "balance", unit: "CNY")
        let rule = candidate.rule()
        XCTAssertEqual(rule.source, .api)
        XCTAssertEqual(rule.apiURL, "https://example.com/api/wallet")
        XCTAssertEqual(rule.apiMethod, "POST")
        XCTAssertEqual(rule.jsonPath, "data.available")
        XCTAssertEqual(rule.domSelector, nil)
        XCTAssertEqual(rule.unit, "CNY")
        // …and the code still displays as money rather than as an empty bar.
        XCTAssertEqual(QuotaUnit.displayAmount(500, unit: rule.unit), "¥500.00")
    }

    // MARK: - Number extraction

    func test_numbers_ignoresDigitsGluedToWords() {
        XCTAssertEqual(CustomProviderRuntime.numbers(in: "￥1,234.50"), [1234.5])
        XCTAssertEqual(CustomProviderRuntime.numbers(in: "abc123"), [])
        XCTAssertEqual(CustomProviderRuntime.numbers(in: "余额100"), [100])
        XCTAssertEqual(CustomProviderRuntime.numbers(in: "5 / 20"), [5, 20])
    }
}
