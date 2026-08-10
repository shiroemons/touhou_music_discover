import assert from "node:assert/strict"
import test from "node:test"

import AdminFilterDisclosureController from "../../app/javascript/controllers/admin_filter_disclosure_controller.js"

function buildController({ mobile = true, userToggled = false, open = true } = {}) {
  const controller = Object.create(AdminFilterDisclosureController.prototype)
  controller.mobileQuery = { matches: mobile }
  controller.userToggled = userToggled
  Object.defineProperty(controller, "element", { value: { open }, writable: true })
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

test("keeps filters open on desktop", () => {
  const controller = buildController({ mobile: false, open: false })

  controller.syncWithViewport()
  assert.equal(controller.element.open, true)
})
