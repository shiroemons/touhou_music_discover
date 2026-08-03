import assert from "node:assert/strict"
import test from "node:test"

import AdminToastController, { showAdminToast } from "../../app/javascript/controllers/admin_toast_controller.mjs"

function buildController() {
  const controller = Object.create(AdminToastController.prototype)
  controller.defaultDurationValue = 3200
  return controller
}

test("normalizes unsupported toast variants to info", () => {
  const controller = buildController()

  assert.equal(controller.normalizeVariant("success"), "success")
  assert.equal(controller.normalizeVariant("unknown"), "info")
})

test("keeps errors and warnings visible until dismissed", () => {
  const controller = buildController()

  assert.equal(controller.durationFor("error"), 0)
  assert.equal(controller.durationFor("warning"), 0)
  assert.equal(controller.durationFor("success"), 3200)
  assert.equal(controller.durationFor("info", "1500"), 1500)
})

test("uses assertive announcements for errors and warnings", () => {
  const controller = buildController()

  assert.equal(controller.roleFor("error"), "alert")
  assert.equal(controller.roleFor("warning"), "alert")
  assert.equal(controller.roleFor("success"), "status")
})

test("dispatches toast details through the shared browser event", () => {
  const previousWindow = globalThis.window
  const events = []
  globalThis.window = {
    dispatchEvent(event) {
      events.push(event)
    }
  }

  try {
    showAdminToast("コピーしました", { variant: "success", duration: 1500 })

    assert.equal(events.length, 1)
    assert.deepEqual(events[0].detail, {
      message: "コピーしました",
      variant: "success",
      duration: 1500
    })
  } finally {
    globalThis.window = previousWindow
  }
})
