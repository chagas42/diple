import Testing
@testable import Diple

@Test func metricsCountsAndResets() {
    let m = Metrics()
    m.count(.requests)
    m.count(.bytesIn, by: 10)
    m.body("NotchView")
    #expect(m.snapshot().count(.requests) == 1)
    #expect(m.snapshot().count(.bytesIn) == 10)
    #expect(m.snapshot().bodies("NotchView") == 1)
    m.reset()
    #expect(m.snapshot().count(.requests) == 0)
}

@Test func metricsMeasuresSpans() {
    let m = Metrics()
    let v = m.measure(.request) { 42 }
    #expect(v == 42)
    #expect(m.snapshot().millis(.request).count == 1)
}
