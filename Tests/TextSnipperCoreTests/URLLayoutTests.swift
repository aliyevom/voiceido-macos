import XCTest
@testable import TextSnipperCore

final class URLLayoutTests: XCTestCase {
    func testWrappedURLBecomesOneLine() {
        let wrapped = """
        2. https://auth.example.org/oauth2/authorize?redirect_uri=https%3A%2F%2Fclient.example.com%2Fcallback
        &scope=openid%20profile%20email&state=xYz987
        4. https://dashboard.example.com/analytics/reports/2026/
        Q4?metrics=revenue,conversion_rate,retention&dimensions=region,device,channel
        7. https://search.example.com/query?q=azure&filters[
        year]=2026&sort=relevance
        """
        let joined = URLLayout.joinWrappedLines(wrapped)
        XCTAssertEqual(
            joined,
            """
            2. https://auth.example.org/oauth2/authorize?redirect_uri=https%3A%2F%2Fclient.example.com%2Fcallback&scope=openid%20profile%20email&state=xYz987
            4. https://dashboard.example.com/analytics/reports/2026/Q4?metrics=revenue,conversion_rate,retention&dimensions=region,device,channel
            7. https://search.example.com/query?q=azure&filters[year]=2026&sort=relevance
            """
        )
    }

    func testURLSplitInsideAWordIsJoined() {
        let wrapped = """
        https://portal.example.com/logs?level=error,warn&s
        tart=2026-11-01T00%3A00%3A00Z&trace=true
        """
        XCTAssertEqual(
            URLLayout.joinWrappedLines(wrapped),
            "https://portal.example.com/logs?level=error,warn&start=2026-11-01T00%3A00%3A00Z&trace=true"
        )
    }

    func testASentenceAfterAURLStaysSeparate() {
        let text = """
        See https://example.com/docs
        Then read the guide.
        """
        XCTAssertEqual(URLLayout.joinWrappedLines(text), text)
    }
}
