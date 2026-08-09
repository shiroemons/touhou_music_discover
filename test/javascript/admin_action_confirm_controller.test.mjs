import assert from "node:assert/strict"
import test from "node:test"

import AdminActionConfirmController from "../../app/javascript/controllers/admin_action_confirm_controller.js"

function buildController() {
  const buttons = [{ disabled: false }, { disabled: false }]
  const attributes = {}
  let closeCalls = 0
  let requestSubmitCalls = 0
  const controller = Object.create(AdminActionConfirmController.prototype)
  const element = {
    querySelectorAll: (selector) => {
      assert.equal(selector, "button")
      return buttons
    },
    requestSubmit: () => {
      requestSubmitCalls += 1
    },
    setAttribute: (name, value) => {
      attributes[name] = value
    }
  }
  const modalTarget = {
    close: () => {
      closeCalls += 1
    }
  }

  controller.confirmed = false
  Object.defineProperty(controller, "element", { value: element })
  Object.defineProperty(controller, "modalTarget", { value: modalTarget })

  return { controller, buttons, attributes, getCloseCalls: () => closeCalls, getRequestSubmitCalls: () => requestSubmitCalls }
}

test("disables action buttons and ignores repeated confirmation", () => {
  const { controller, buttons, attributes, getCloseCalls, getRequestSubmitCalls } = buildController()

  controller.confirm()
  controller.confirm()

  assert.equal(controller.confirmed, true)
  assert.deepEqual(buttons.map((button) => button.disabled), [true, true])
  assert.equal(attributes["aria-busy"], "true")
  assert.equal(getCloseCalls(), 1)
  assert.equal(getRequestSubmitCalls(), 1)
})
