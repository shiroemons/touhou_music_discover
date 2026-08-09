import assert from "node:assert/strict"
import test from "node:test"

import AdminAssociationSelectController from "../../app/javascript/controllers/admin_association_select_controller.js"

function buildController() {
  const controller = Object.create(AdminAssociationSelectController.prototype)
  controller.hasUrlValue = true
  controller.urlValue = "/admin/association-options"
  controller.loadedQuery = null
  controller.requestSequence = 0
  controller.multipleValue = false
  controller.selectedValue = ""
  controller.selectedValues = []
  controller.visibleOptions = () => []
  controller.updateActiveOption = () => {}
  controller.inputTarget = {
    removeAttribute() {}
  }
  controller.listboxTarget = {
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    removeAttribute(name) {
      delete this.attributes[name]
    }
  }
  controller.renderOptions = (options) => {
    controller.renderedOptions = options
    controller.errorShown = false
  }
  controller.renderError = (retryAction) => {
    controller.retryAction = retryAction
    controller.errorShown = true
  }
  return controller
}

test("shows a retryable error instead of clearing association options after failure", async () => {
  const previousFetch = globalThis.fetch
  const previousWindow = globalThis.window
  const requests = []
  let attempt = 0
  globalThis.window = { location: { origin: "http://example.test" } }
  globalThis.fetch = async (url) => {
    requests.push(url.toString())
    attempt += 1
    if (attempt === 1) return { ok: false, status: 503 }

    return {
      ok: true,
      json: async () => ({ options: [{ value: "album-1", label: "Album 1" }] })
    }
  }

  try {
    const controller = buildController()
    await controller.loadOptions("Album", { activateFirst: true })

    assert.equal(controller.errorShown, true)
    assert.equal(controller.renderedOptions, undefined)
    assert.equal(typeof controller.retryAction, "function")

    await controller.retry({ preventDefault() {} })

    assert.deepEqual(controller.renderedOptions, [{ value: "album-1", label: "Album 1" }])
    assert.equal(controller.errorShown, false)
    assert.equal(requests.length, 2)
    assert.equal(new URL(requests[0]).searchParams.get("q"), "Album")
    assert.equal(new URL(requests[1]).searchParams.get("q"), "Album")
    assert.equal(controller.listboxTarget.attributes["aria-busy"], undefined)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.window = previousWindow
  }
})

test("ignores a stale association failure after a newer query has started", async () => {
  const previousFetch = globalThis.fetch
  const previousWindow = globalThis.window
  const pending = {}
  globalThis.window = { location: { origin: "http://example.test" } }
  globalThis.fetch = async (url) => new Promise((resolve) => {
    pending[new URL(url).searchParams.get("q")] = resolve
  })

  try {
    const controller = buildController()
    const oldRequest = controller.loadOptions("old", { activateFirst: true })
    const newRequest = controller.loadOptions("new", { activateFirst: true })

    pending.new({
      ok: true,
      json: async () => ({ options: [{ value: "new-album", label: "New Album" }] })
    })
    await newRequest

    pending.old({ ok: false, status: 503 })
    await oldRequest

    assert.deepEqual(controller.renderedOptions, [{ value: "new-album", label: "New Album" }])
    assert.equal(controller.errorShown, false)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.window = previousWindow
  }
})
