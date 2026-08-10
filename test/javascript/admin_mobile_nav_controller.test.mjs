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

function buildController({ mobile = true } = {}) {
  const controller = Object.create(AdminMobileNavController.prototype)
  controller.mobileQuery = { matches: mobile }
  controller.drawerTarget = {
    attributes: {},
    classList: classList(),
    inert: false,
    setAttribute(name, value) {
      this.attributes[name] = value
    }
  }
  controller.openTarget = {
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    focus() {
      this.focused = true
    },
    focused: false
  }
  controller.closeTarget = {
    focus() {
      this.focused = true
    },
    focused: false
  }
  controller.backdropTarget = {
    attributes: {},
    classList: classList(),
    hidden: true,
    setAttribute(name, value) {
      this.attributes[name] = value
    }
  }
  return controller
}

test("collapses the navigation on mobile and exposes the expanded state", () => {
  const controller = buildController()

  controller.setOpen(false)

  assert.equal(controller.drawerTarget.classList.contains("is-open"), false)
  assert.equal(controller.drawerTarget.attributes["aria-hidden"], "true")
  assert.equal(controller.drawerTarget.inert, true)
  assert.equal(controller.backdropTarget.hidden, true)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "false")

  controller.open()

  assert.equal(controller.drawerTarget.classList.contains("is-open"), true)
  assert.equal(controller.drawerTarget.attributes["aria-hidden"], "false")
  assert.equal(controller.drawerTarget.inert, false)
  assert.equal(controller.backdropTarget.hidden, false)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "true")
  assert.equal(controller.closeTarget.focused, true)

  controller.close()

  assert.equal(controller.drawerTarget.classList.contains("is-open"), false)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "false")
  assert.equal(controller.openTarget.focused, true)
})

test("keeps the navigation open on desktop", () => {
  const controller = buildController({ mobile: false })

  controller.setOpen(false)

  assert.equal(controller.drawerTarget.classList.contains("is-open"), true)
  assert.equal(controller.drawerTarget.attributes["aria-hidden"], "false")
  assert.equal(controller.drawerTarget.inert, false)
  assert.equal(controller.backdropTarget.hidden, true)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "true")
})
