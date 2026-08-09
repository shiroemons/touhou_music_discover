import assert from "node:assert/strict"
import test from "node:test"

import AdminInfiniteScrollController from "../../app/javascript/controllers/admin_infinite_scroll_controller.js"

function buildController() {
  const controller = Object.create(AdminInfiniteScrollController.prototype)
  controller.nextUrlValue = "/admin/circles?page=2"
  controller.loading = false
  controller.paused = false
  controller.abortController = null
  controller.hasStatusTarget = true
  controller.statusTarget = {
    dataset: {},
    textContent: ""
  }
  controller.hasRetryTarget = true
  controller.retryTarget = { hidden: true }
  controller.rowsTarget = {
    appended: [],
    appendChild(row) {
      this.appended.push(row)
    }
  }
  controller.hideRetry = () => {
    controller.retryTarget.hidden = true
  }
  controller.showRetry = () => {
    controller.retryTarget.hidden = false
  }
  controller.finished = false
  controller.finish = () => {
    controller.finished = true
  }
  return controller
}

test("shows retry controls when a successful response is not an infinite-scroll page", async () => {
  const previousFetch = globalThis.fetch
  const previousDOMParser = globalThis.DOMParser
  globalThis.fetch = async () => ({
    ok: true,
    text: async () => "<html><body>ログイン画面</body></html>"
  })
  globalThis.DOMParser = class {
    parseFromString() {
      return {
        querySelector() {
          return null
        }
      }
    }
  }

  try {
    const controller = buildController()
    await controller.loadNextPage()

    assert.equal(controller.paused, true)
    assert.equal(controller.loading, false)
    assert.equal(controller.finished, false)
    assert.equal(controller.rowsTarget.appended.length, 0)
    assert.equal(controller.statusTarget.textContent, "読み込みに失敗しました")
    assert.equal(controller.retryTarget.hidden, false)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.DOMParser = previousDOMParser
  }
})
