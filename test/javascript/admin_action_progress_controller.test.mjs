import assert from "node:assert/strict"
import test from "node:test"

import AdminActionProgressController from "../../app/javascript/controllers/admin_action_progress_controller.js"

function buildController() {
  const controller = Object.create(AdminActionProgressController.prototype)
  controller.polling = true
  controller.fetching = false
  controller.timer = null
  controller.hasErrorTarget = true
  controller.hasRetryTarget = true
  controller.errorTarget = { hidden: true }
  controller.retryTarget = { hidden: true }
  return controller
}

test("stops polling and exposes retry controls when progress retrieval fails", async () => {
  const previousFetch = globalThis.fetch
  const previousConsoleError = console.error
  globalThis.fetch = async () => ({ ok: false, status: 503 })
  console.error = () => {}

  try {
    const controller = buildController()
    await controller.fetchProgress()

    assert.equal(controller.polling, false)
    assert.equal(controller.errorTarget.hidden, false)
    assert.equal(controller.retryTarget.hidden, false)
  } finally {
    globalThis.fetch = previousFetch
    console.error = previousConsoleError
  }
})

test("retry resumes progress retrieval and hides the retry controls", () => {
  const controller = buildController()
  controller.polling = false
  controller.errorTarget.hidden = false
  controller.retryTarget.hidden = false
  let fetchCalls = 0
  controller.fetchProgress = () => {
    fetchCalls += 1
  }

  controller.retry()

  assert.equal(controller.polling, true)
  assert.equal(controller.errorTarget.hidden, true)
  assert.equal(controller.retryTarget.hidden, true)
  assert.equal(fetchCalls, 1)
})
