import assert from "node:assert/strict"
import test from "node:test"

import AdminFilterDisclosureController from "../../app/javascript/controllers/admin_filter_disclosure_controller.js"

function buildController({ mobile = true, userToggled = false, open = true, hasActiveFilters = false } = {}) {
  const controller = Object.create(AdminFilterDisclosureController.prototype)
  controller.mobileQuery = { matches: mobile }
  controller.userToggled = userToggled
  controller.hasActiveFilters = hasActiveFilters
  Object.defineProperty(controller, "element", {
    value: { open, dataset: { adminFilterDisclosureActive: hasActiveFilters ? "true" : "false" } },
    writable: true
  })
  controller.summary = {
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    }
  }
  return controller
}

test("collapses filters by default on mobile and reopens them when toggled", () => {
  const controller = buildController()

  controller.syncWithViewport()
  assert.equal(controller.element.open, false)

  controller.userToggled = true
  controller.syncWithViewport()
  assert.equal(controller.element.open, true)
})

test("keeps the expanded state available to assistive technology", () => {
  const controller = buildController({ mobile: true })

  controller.syncWithViewport()
  assert.equal(controller.summary.attributes["aria-expanded"], "false")

  controller.userToggled = true
  controller.syncWithViewport()
  assert.equal(controller.summary.attributes["aria-expanded"], "true")
})

test("keeps filters open on desktop", () => {
  const controller = buildController({ mobile: false, open: false })

  controller.syncWithViewport()
  assert.equal(controller.element.open, true)
})

test("keeps active filters visible on mobile by default", () => {
  const controller = buildController({ hasActiveFilters: true })

  controller.syncWithViewport()
  assert.equal(controller.element.open, true)
})
