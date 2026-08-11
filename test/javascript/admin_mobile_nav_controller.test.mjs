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
  controller.context = { scope: { element: { classList: classList() } } }
  controller.mobileQuery = { matches: mobile }
  controller.mobileLabelValue = "メニュー"
  controller.mobileCloseLabelValue = "メニューを閉じる"
  controller.desktopOpenLabelValue = "サイドバーを表示"
  controller.desktopCloseLabelValue = "サイドバーを隠す"
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
  controller.openLabelTarget = { textContent: "" }
  controller.closeTarget = {
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    },
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
  assert.equal(controller.openTarget.attributes["aria-label"], "メニュー")

  controller.toggle()

  assert.equal(controller.drawerTarget.classList.contains("is-open"), true)
  assert.equal(controller.drawerTarget.attributes["aria-hidden"], "false")
  assert.equal(controller.drawerTarget.inert, false)
  assert.equal(controller.backdropTarget.hidden, false)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "true")
  assert.equal(controller.openTarget.attributes["aria-label"], "メニューを閉じる")
  assert.equal(controller.closeTarget.focused, true)

  controller.close()

  assert.equal(controller.drawerTarget.classList.contains("is-open"), false)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "false")
  assert.equal(controller.openTarget.attributes["aria-label"], "メニュー")
  assert.equal(controller.openTarget.focused, true)
})

test("supports closing and reopening the navigation on desktop", () => {
  const controller = buildController({ mobile: false })

  controller.setOpen(false)

  assert.equal(controller.drawerTarget.classList.contains("is-open"), false)
  assert.equal(controller.drawerTarget.attributes["aria-hidden"], "true")
  assert.equal(controller.drawerTarget.inert, true)
  assert.equal(controller.backdropTarget.hidden, true)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "false")
  assert.equal(controller.openTarget.attributes["aria-label"], "サイドバーを表示")

  controller.toggle()

  assert.equal(controller.drawerTarget.classList.contains("is-open"), true)
  assert.equal(controller.drawerTarget.attributes["aria-hidden"], "false")
  assert.equal(controller.drawerTarget.inert, false)
  assert.equal(controller.openTarget.attributes["aria-expanded"], "true")
  assert.equal(controller.openTarget.attributes["aria-label"], "サイドバーを隠す")
  assert.equal(controller.closeTarget.attributes["aria-label"], "サイドバーを隠す")
  assert.equal(controller.closeTarget.focused, true)
})
