final class Fixture {
    var replies: [Bool] = []
    var finishes: [[Bool]] = []
    var stops: [(Bool) -> Void] = []
    var expiry: (() -> Void)?
    var disposeSucceeds = true
    var deadlineCount = 0
    lazy var gate = OfflineCacheShutdownGate(
        requestStop: { [unowned self] in self.stops.append($0) },
        armDeadline: { [unowned self] expired in
            self.deadlineCount += 1
            self.expiry = expired
            return { [unowned self] in self.expiry = nil }
        },
        finish: { [unowned self] graceful, stopping in
            self.finishes.append([graceful, stopping])
            precondition(self.replies.isEmpty || self.replies.allSatisfy { !$0 })
            return self.disposeSucceeds
        }
    )
    func cancel() { gate.cancel { [unowned self] in self.replies.append($0) } }
    func expire() { expiry!() }
    func assertState(_ replies: [Bool], _ finishes: Int, _ stops: Int) {
        precondition(self.replies == replies)
        precondition(self.finishes.count == finishes)
        precondition(self.stops.count == stops)
    }
}

func scenario(_ name: String, _ work: () -> Void) {
    work()
    print("PASS \(name)")
}

scenario("normal_completion") {
    let f = Fixture()
    precondition(f.gate.markReady())
    f.gate.complete()
    precondition(f.finishes == [[true, false]])
    f.cancel()
    f.assertState([true], 1, 0)
}
scenario("cancel_before_ready") {
    let f = Fixture()
    f.cancel()
    f.assertState([], 0, 0)
    precondition(!f.gate.markReady())
    f.assertState([], 0, 1)
    f.stops[0](true)
    f.assertState([true], 1, 1)
    precondition(f.finishes == [[true, true]])
    precondition(f.expiry == nil)
}
scenario("coalesced_cancellation") {
    let f = Fixture()
    precondition(f.gate.markReady())
    f.cancel()
    f.cancel()
    precondition(f.deadlineCount == 1)
    f.stops[0](true)
    f.assertState([true, true], 1, 1)
}
scenario("timeout_does_not_destroy") {
    let f = Fixture()
    _ = f.gate.markReady()
    f.cancel()
    f.expire()
    f.assertState([false], 0, 1)
    f.cancel()
    precondition(f.deadlineCount == 2)
    f.stops[0](true)
    f.assertState([false, true], 1, 1)
}
scenario("timeout_before_ready") {
    let f = Fixture()
    f.cancel()
    f.expire()
    f.assertState([false], 0, 0)
    f.cancel()
    precondition(!f.gate.markReady())
    f.stops[0](true)
    f.assertState([false, true], 1, 1)
}
scenario("negative_reply_can_retry") {
    let f = Fixture()
    _ = f.gate.markReady()
    f.cancel()
    f.stops[0](false)
    f.assertState([false], 0, 1)
    precondition(f.expiry == nil)
    f.cancel()
    f.stops.last!(true)
    f.assertState([false, true], 1, 2)
}
scenario("forced_termination_is_not_acknowledgment") {
    let f = Fixture()
    _ = f.gate.markReady()
    f.cancel()
    f.gate.terminate()
    f.stops[0](true)
    f.cancel()
    f.assertState([false, false], 1, 1)
    precondition(f.finishes == [[false, true]])
    precondition(!f.gate.markReady())
}
scenario("failed_disposal_never_acknowledges") {
    let f = Fixture()
    f.disposeSucceeds = false
    _ = f.gate.markReady()
    f.cancel()
    f.stops[0](true)
    f.cancel()
    f.assertState([false, false], 1, 1)
}
scenario("completion_wins_stop_reply_race") {
    let f = Fixture()
    _ = f.gate.markReady()
    f.cancel()
    f.gate.complete()
    f.stops[0](false)
    f.gate.terminate()
    f.assertState([true], 1, 1)
}
scenario("stop_reply_wins_completion_race") {
    let f = Fixture()
    _ = f.gate.markReady()
    f.cancel()
    f.stops[0](true)
    f.gate.complete()
    f.gate.terminate()
    f.assertState([true], 1, 1)
}
scenario("reentrant_waiter_observes_disposed_engine") {
    let f = Fixture()
    _ = f.gate.markReady()
    f.gate.cancel { stopped in
        precondition(stopped && f.finishes.count == 1)
        f.cancel()
    }
    f.stops[0](true)
    f.assertState([true], 1, 1)
}
scenario("synchronous_stop_reply") {
    var replies: [Bool] = []
    var finished = false
    let gate = OfflineCacheShutdownGate(
        requestStop: { $0(true) },
        armDeadline: { _ in { } },
        finish: { graceful, stopping in finished = graceful && stopping; return finished }
    )
    _ = gate.markReady()
    gate.cancel { precondition(finished); replies.append($0) }
    precondition(replies == [true])
}
scenario("no_work_reopens_after_termination") {
    let f = Fixture()
    f.gate.terminate()
    f.cancel()
    precondition(!f.gate.markReady())
    f.gate.complete()
    f.assertState([false], 1, 0)
}
scenario("complete_after_timeout") {
    let f = Fixture()
    f.cancel()
    f.expire()
    f.gate.complete()
    f.cancel()
    f.assertState([false, true], 1, 0)
}
