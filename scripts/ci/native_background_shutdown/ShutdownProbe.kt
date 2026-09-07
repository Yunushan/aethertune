private class Fixture {
    val replies = mutableListOf<Boolean>()
    val finishes = mutableListOf<Pair<Boolean, Boolean>>()
    val stops = mutableListOf<(Boolean) -> Unit>()
    var expiry: (() -> Unit)? = null
    var disposeSucceeds = true
    var deadlineCount = 0
    val gate = OfflineCacheShutdownGate(
        requestStop = { stops.add(it) },
        armDeadline = { expired ->
            deadlineCount++
            expiry = expired
            val cancel: () -> Unit = { expiry = null }
            cancel
        },
        finish = { graceful, stopping ->
            finishes.add(Pair(graceful, stopping))
            check(replies.isEmpty() || replies.all { !it })
            disposeSucceeds
        },
    )
    fun cancel() { gate.cancel { replies.add(it) } }
    fun expire() { checkNotNull(expiry).invoke() }
    fun assertState(replies: List<Boolean>, finishes: Int, stops: Int) {
        check(this.replies == replies) { "Replies: ${this.replies}, expected $replies" }
        check(this.finishes.size == finishes)
        check(this.stops.size == stops)
    }
}

private fun scenario(name: String, work: () -> Unit) {
    work()
    println("PASS $name")
}

fun main() {
    scenario("normal_completion") {
        val f = Fixture()
        check(f.gate.markReady())
        f.gate.complete()
        check(f.finishes == listOf(Pair(true, false)))
        f.cancel()
        f.assertState(listOf(true), 1, 0)
    }
    scenario("cancel_before_ready") {
        val f = Fixture()
        f.cancel()
        f.assertState(emptyList(), 0, 0)
        check(!f.gate.markReady())
        f.assertState(emptyList(), 0, 1)
        f.stops.single()(true)
        f.assertState(listOf(true), 1, 1)
        check(f.finishes == listOf(Pair(true, true)))
        check(f.expiry == null)
    }
    scenario("coalesced_cancellation") {
        val f = Fixture()
        check(f.gate.markReady())
        f.cancel()
        f.cancel()
        check(f.deadlineCount == 1)
        f.stops.single()(true)
        f.assertState(listOf(true, true), 1, 1)
    }
    scenario("timeout_does_not_destroy") {
        val f = Fixture()
        f.gate.markReady()
        f.cancel()
        f.expire()
        f.assertState(listOf(false), 0, 1)
        f.cancel()
        check(f.deadlineCount == 2)
        f.stops.single()(true)
        f.assertState(listOf(false, true), 1, 1)
    }
    scenario("timeout_before_ready") {
        val f = Fixture()
        f.cancel()
        f.expire()
        f.assertState(listOf(false), 0, 0)
        f.cancel()
        check(!f.gate.markReady())
        f.stops.single()(true)
        f.assertState(listOf(false, true), 1, 1)
    }
    scenario("negative_reply_can_retry") {
        val f = Fixture()
        f.gate.markReady()
        f.cancel()
        f.stops.single()(false)
        f.assertState(listOf(false), 0, 1)
        check(f.expiry == null)
        f.cancel()
        f.stops.last()(true)
        f.assertState(listOf(false, true), 1, 2)
    }
    scenario("forced_termination_is_not_acknowledgment") {
        val f = Fixture()
        f.gate.markReady()
        f.cancel()
        f.gate.terminate()
        f.stops.single()(true)
        f.cancel()
        f.assertState(listOf(false, false), 1, 1)
        check(f.finishes == listOf(Pair(false, true)))
        check(!f.gate.markReady())
    }
    scenario("failed_disposal_never_acknowledges") {
        val f = Fixture()
        f.disposeSucceeds = false
        f.gate.markReady()
        f.cancel()
        f.stops.single()(true)
        f.cancel()
        f.assertState(listOf(false, false), 1, 1)
    }
    scenario("completion_wins_stop_reply_race") {
        val f = Fixture()
        f.gate.markReady()
        f.cancel()
        f.gate.complete()
        f.stops.single()(false)
        f.gate.terminate()
        f.assertState(listOf(true), 1, 1)
    }
    scenario("stop_reply_wins_completion_race") {
        val f = Fixture()
        f.gate.markReady()
        f.cancel()
        f.stops.single()(true)
        f.gate.complete()
        f.gate.terminate()
        f.assertState(listOf(true), 1, 1)
    }
    scenario("reentrant_waiter_observes_disposed_engine") {
        val f = Fixture()
        f.gate.markReady()
        f.gate.cancel { stopped ->
            check(stopped && f.finishes.size == 1)
            f.cancel()
        }
        f.stops.single()(true)
        f.assertState(listOf(true), 1, 1)
    }
    scenario("synchronous_stop_reply") {
        val replies = mutableListOf<Boolean>()
        var finished = false
        val gate = OfflineCacheShutdownGate(
            requestStop = { it(true) },
            armDeadline = { { } },
            finish = { graceful, stopping -> finished = graceful && stopping; finished },
        )
        gate.markReady()
        gate.cancel { check(finished); replies.add(it) }
        check(replies == listOf(true))
    }
    scenario("no_work_reopens_after_termination") {
        val f = Fixture()
        f.gate.terminate()
        f.cancel()
        check(!f.gate.markReady())
        f.gate.complete()
        f.assertState(listOf(false), 1, 0)
    }
    scenario("complete_after_timeout") {
        val f = Fixture()
        f.cancel()
        f.expire()
        f.gate.complete()
        f.cancel()
        f.assertState(listOf(false, true), 1, 0)
    }
}
