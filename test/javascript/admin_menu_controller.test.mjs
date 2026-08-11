import assert from "node:assert/strict"
import test from "node:test"

import AdminMenuController from "../../app/javascript/controllers/admin_menu_controller.js"

function eventTarget() {
  const listeners = new Map()

  return {
    addEventListener(type, listener) {
      listeners.set(type, listener)
    },
    removeEventListener(type, listener) {
      if (listeners.get(type) === listener) listeners.delete(type)
    },
    dispatch(type, event) {
      listeners.get(type)?.(event)
    }
  }
}

function buildController({ open = true } = {}) {
  const documentTarget = eventTarget()
  const elementTarget = eventTarget()
  const insideTarget = { closest: () => null }
  const outsideTarget = { closest: () => null }
  const summary = {
    attributes: {},
    focused: false,
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    focus() {
      this.focused = true
    }
  }
  const element = {
    open,
    contains(target) {
      return target === this || target === summary || target === insideTarget
    },
    querySelector() {
      return summary
    },
    addEventListener: (...args) => elementTarget.addEventListener(...args),
    removeEventListener: (...args) => elementTarget.removeEventListener(...args)
  }
  const controller = Object.create(AdminMenuController.prototype)

  Object.defineProperty(controller, "element", { value: element })
  globalThis.document = {
    addEventListener: (...args) => documentTarget.addEventListener(...args),
    removeEventListener: (...args) => documentTarget.removeEventListener(...args),
    querySelectorAll: () => []
  }
  controller.connect()

  return {
    controller,
    documentTarget,
    insideTarget,
    outsideTarget,
    summary,
    restore() {
      delete globalThis.document
    }
  }
}

test("closes an open menu when the pointer moves outside it", () => {
  const fixture = buildController()

  try {
    fixture.documentTarget.dispatch("pointerdown", { target: fixture.outsideTarget })

    assert.equal(fixture.controller.element.open, false)
    assert.equal(fixture.summary.focused, false)
    assert.equal(fixture.summary.attributes["aria-expanded"], "false")
  } finally {
    fixture.restore()
  }
})

test("closes on Escape and returns focus to the trigger", () => {
  const fixture = buildController()
  let prevented = false

  try {
    fixture.documentTarget.dispatch("keydown", {
      key: "Escape",
      preventDefault() {
        prevented = true
      }
    })

    assert.equal(fixture.controller.element.open, false)
    assert.equal(prevented, true)
    assert.equal(fixture.summary.focused, true)
  } finally {
    fixture.restore()
  }
})
