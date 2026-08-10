import assert from "node:assert/strict"
import test from "node:test"

import AdminMobileNavController from "../../app/javascript/controllers/admin_mobile_nav_controller.js"

function classList() {
  const values = new Set()

  return {
    contains(value) {
      return values.has(value)
    },
    toggle(value, force) {
      const shouldAdd = force ?? !values.has(value)
      if (shouldAdd) values.add(value)
      else values.delete(value)
    }
  }
}

function buildController() {
  const controller = Object.create(AdminMobileNavController.prototype)
  controller.mobileQuery = { matches: true }
  controller.menuTarget = { classList: classList() }
  controller.toggleTarget = {
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    }
  }
  return controller
}

test("collapses the navigation on mobile and exposes the expanded state", () => {
  const controller = buildController()

  controller.setOpen(false)

  assert.equal(controller.menuTarget.classList.contains("is-collapsed"), true)
  assert.equal(controller.menuTarget.classList.contains("is-open"), false)
  assert.equal(controller.toggleTarget.attributes["aria-expanded"], "false")

  controller.toggle()

  assert.equal(controller.menuTarget.classList.contains("is-collapsed"), false)
  assert.equal(controller.menuTarget.classList.contains("is-open"), true)
  assert.equal(controller.toggleTarget.attributes["aria-expanded"], "true")
})

test("keeps the navigation open on desktop", () => {
  const controller = buildController()
  controller.mobileQuery.matches = false

  controller.setOpen(false)

  assert.equal(controller.menuTarget.classList.contains("is-collapsed"), false)
  assert.equal(controller.menuTarget.classList.contains("is-open"), true)
  assert.equal(controller.toggleTarget.attributes["aria-expanded"], "true")
})
