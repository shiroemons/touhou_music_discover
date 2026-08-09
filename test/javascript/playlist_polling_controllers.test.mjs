import assert from "node:assert/strict"
import test from "node:test"

import ProgressPollingController from "../../app/javascript/controllers/progress_polling_controller.js"
import PlaylistRefreshPollingController from "../../app/javascript/controllers/playlist_refresh_polling_controller.js"

function buildController(ControllerClass, url) {
  const controller = Object.create(ControllerClass.prototype)
  controller.urlValue = url
  controller.fetching = false
  controller.timer = null
  controller.errorShown = false
  controller.pollStarted = 0
  controller.pollStopped = 0
  controller.showError = () => {
    controller.errorShown = true
  }
  controller.hideError = () => {
    controller.errorShown = false
  }
  controller.poll = () => {
    controller.pollStarted += 1
  }
  controller.stopPolling = () => {
    controller.pollStopped += 1
    controller.timer = null
  }
  return controller
}

test("skips overlapping progress polling requests", async () => {
  const previousFetch = globalThis.fetch
  const previousConsoleError = console.error
  let fetchCalls = 0
  let resolveFetch
  globalThis.fetch = async () => {
    fetchCalls += 1
    return new Promise((resolve) => {
      resolveFetch = resolve
    })
  }
  console.error = () => {}

  try {
    const controller = buildController(ProgressPollingController, "/playlists/progress_stream")
    const firstRequest = controller.fetchProgress()
    const skippedRequest = await controller.fetchProgress()

    assert.equal(skippedRequest, undefined)
    assert.equal(fetchCalls, 1)
    assert.equal(controller.fetching, true)

    resolveFetch({ ok: false, status: 503 })
    await firstRequest
    assert.equal(controller.fetching, false)
    assert.equal(controller.pollStopped, 1)
    assert.equal(controller.errorShown, true)
  } finally {
    globalThis.fetch = previousFetch
    console.error = previousConsoleError
  }
})

test("skips overlapping playlist count refresh requests", async () => {
  const previousFetch = globalThis.fetch
  const previousConsoleError = console.error
  let fetchCalls = 0
  let resolveFetch
  globalThis.fetch = async () => {
    fetchCalls += 1
    return new Promise((resolve) => {
      resolveFetch = resolve
    })
  }
  console.error = () => {}

  try {
    const controller = buildController(PlaylistRefreshPollingController, "/playlists/refresh_counts_stream")
    const firstRequest = controller.fetchRefreshCounts()
    const skippedRequest = await controller.fetchRefreshCounts()

    assert.equal(skippedRequest, undefined)
    assert.equal(fetchCalls, 1)
    assert.equal(controller.fetching, true)

    resolveFetch({ ok: false, status: 503 })
    await firstRequest
    assert.equal(controller.fetching, false)
    assert.equal(controller.pollStopped, 1)
    assert.equal(controller.errorShown, true)
  } finally {
    globalThis.fetch = previousFetch
    console.error = previousConsoleError
  }
})

test("retries a failed progress request from the visible error state", async () => {
  const previousFetch = globalThis.fetch
  const previousConsoleError = console.error
  const previousTurbo = globalThis.Turbo
  const previousDocument = globalThis.document
  let fetchCalls = 0
  globalThis.fetch = async () => {
    fetchCalls += 1
    if (fetchCalls === 1) return { ok: false, status: 503 }

    return { ok: true, text: async () => "" }
  }
  globalThis.Turbo = { renderStreamMessage() {} }
  globalThis.document = { querySelector: () => null }
  console.error = () => {}

  try {
    const controller = buildController(ProgressPollingController, "/playlists/progress_stream")
    await controller.fetchProgress()
    assert.equal(controller.errorShown, true)

    await controller.retry()

    assert.equal(fetchCalls, 2)
    assert.equal(controller.errorShown, false)
    assert.equal(controller.pollStarted, 1)
    assert.equal(controller.fetching, false)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.Turbo = previousTurbo
    globalThis.document = previousDocument
    console.error = previousConsoleError
  }
})

test("retries a failed playlist count request from the visible error state", async () => {
  const previousFetch = globalThis.fetch
  const previousConsoleError = console.error
  const previousTurbo = globalThis.Turbo
  const previousDocument = globalThis.document
  let fetchCalls = 0
  globalThis.fetch = async () => {
    fetchCalls += 1
    if (fetchCalls === 1) return { ok: false, status: 503 }

    return { ok: true, text: async () => "" }
  }
  globalThis.Turbo = { renderStreamMessage() {} }
  globalThis.document = { querySelector: () => null }
  console.error = () => {}

  try {
    const controller = buildController(PlaylistRefreshPollingController, "/playlists/refresh_counts_stream")
    await controller.fetchRefreshCounts()
    assert.equal(controller.errorShown, true)

    await controller.retry()

    assert.equal(fetchCalls, 2)
    assert.equal(controller.errorShown, false)
    assert.equal(controller.pollStarted, 1)
    assert.equal(controller.fetching, false)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.Turbo = previousTurbo
    globalThis.document = previousDocument
    console.error = previousConsoleError
  }
})
