import assert from "node:assert/strict"
import test from "node:test"

import ProgressPollingController from "../../app/javascript/controllers/progress_polling_controller.js"
import PlaylistRefreshPollingController from "../../app/javascript/controllers/playlist_refresh_polling_controller.js"

function buildController(ControllerClass, url) {
  const controller = Object.create(ControllerClass.prototype)
  controller.urlValue = url
  controller.fetching = false
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
  } finally {
    globalThis.fetch = previousFetch
    console.error = previousConsoleError
  }
})
