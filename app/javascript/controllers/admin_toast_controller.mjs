import { Controller } from "@hotwired/stimulus"

const TOAST_EVENT = "admin:toast"
const DEFAULT_DURATION = 3200
const DISMISS_ANIMATION_DURATION = 180
const PERSISTENT_VARIANTS = new Set(["error", "warning"])
const VARIANTS = new Set(["success", "error", "warning", "info"])

export function showAdminToast(message, { variant = "success", duration } = {}) {
  if (!message || typeof window === "undefined") return

  window.dispatchEvent(new CustomEvent(TOAST_EVENT, {
    detail: { message, variant, duration }
  }))
}

export default class extends Controller {
  static targets = ["item"]
  static values = {
    defaultDuration: { type: Number, default: DEFAULT_DURATION },
    dismissLabel: { type: String, default: "通知を閉じる" }
  }

  connect() {
    this.timers = new Map()
    this.removalTimers = new Map()
    this.handleToast = (event) => this.show(event.detail || {})

    window.addEventListener(TOAST_EVENT, this.handleToast)
    this.itemTargets.forEach((item) => this.scheduleDismiss(item))
  }

  disconnect() {
    window.removeEventListener(TOAST_EVENT, this.handleToast)
    this.timers.forEach((timer) => window.clearTimeout(timer))
    this.removalTimers.forEach((timer) => window.clearTimeout(timer))
    this.timers.clear()
    this.removalTimers.clear()
  }

  show({ message, variant = "success", duration } = {}) {
    const normalizedMessage = String(message ?? "").trim()
    if (!normalizedMessage) return

    const normalizedVariant = this.normalizeVariant(variant)
    const item = this.createItem(normalizedMessage, normalizedVariant)

    this.element.append(item)
    this.scheduleDismiss(item, duration)
  }

  dismiss(event) {
    const item = event?.currentTarget?.closest?.("[data-admin-toast-target='item']") || event
    if (!item || item.dataset.adminToastState === "leaving") return

    this.clearTimer(item)
    item.dataset.adminToastState = "leaving"

    const removalTimer = window.setTimeout(() => {
      item.remove()
      this.removalTimers.delete(item)
    }, DISMISS_ANIMATION_DURATION)

    this.removalTimers.set(item, removalTimer)
  }

  createItem(message, variant) {
    const item = document.createElement("div")
    item.className = `alert alert-${variant} admin-toast-item`
    item.dataset.adminToastTarget = "item"
    item.dataset.adminToastVariant = variant
    item.setAttribute("role", this.roleFor(variant))
    item.setAttribute("aria-atomic", "true")

    const messageElement = document.createElement("span")
    messageElement.className = "admin-toast-message"
    messageElement.textContent = message

    const dismissButton = document.createElement("button")
    dismissButton.type = "button"
    dismissButton.className = "btn btn-circle btn-xs admin-toast-dismiss"
    dismissButton.setAttribute("aria-label", this.dismissLabelValue)
    dismissButton.dataset.action = "admin-toast#dismiss"
    dismissButton.textContent = "×"

    item.append(messageElement, dismissButton)
    return item
  }

  scheduleDismiss(item, duration) {
    this.clearTimer(item)

    const dismissAfter = this.durationFor(item.dataset.adminToastVariant, duration ?? item.dataset.adminToastDuration)
    if (dismissAfter === 0) return

    this.timers.set(item, window.setTimeout(() => this.dismiss(item), dismissAfter))
  }

  durationFor(variant, duration) {
    if (duration !== undefined && duration !== null && duration !== "") {
      const normalizedDuration = Number(duration)
      if (Number.isFinite(normalizedDuration) && normalizedDuration >= 0) return normalizedDuration
    }

    return PERSISTENT_VARIANTS.has(variant) ? 0 : this.defaultDurationValue
  }

  normalizeVariant(variant) {
    return VARIANTS.has(variant) ? variant : "info"
  }

  roleFor(variant) {
    return ["error", "warning"].includes(variant) ? "alert" : "status"
  }

  clearTimer(item) {
    const timer = this.timers.get(item)
    if (timer === undefined) return

    window.clearTimeout(timer)
    this.timers.delete(item)
  }
}
