import { Controller } from "@hotwired/stimulus"

const MENU_SELECTOR = 'details[data-controller~="admin-menu"], details.admin-theme-switcher'

export default class extends Controller {
  connect() {
    this.summary = this.element.querySelector(":scope > summary") || this.element.querySelector("summary")
    this.toggleListener = () => this.handleToggle()
    this.pointerDownListener = (event) => this.closeWhenOutside(event)
    this.focusInListener = (event) => this.closeWhenFocusMovesOutside(event)
    this.keydownListener = (event) => this.closeOnEscape(event)
    this.clickListener = (event) => this.closeAfterSelection(event)
    this.beforeCacheListener = () => this.close({ restoreFocus: false })

    this.element.addEventListener("toggle", this.toggleListener)
    document.addEventListener("pointerdown", this.pointerDownListener)
    document.addEventListener("focusin", this.focusInListener)
    document.addEventListener("keydown", this.keydownListener)
    document.addEventListener("click", this.clickListener)
    document.addEventListener("turbo:before-cache", this.beforeCacheListener)
    this.syncSummaryState()

    if (this.element.open) this.closeOtherMenus()
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.toggleListener)
    document.removeEventListener("pointerdown", this.pointerDownListener)
    document.removeEventListener("focusin", this.focusInListener)
    document.removeEventListener("keydown", this.keydownListener)
    document.removeEventListener("click", this.clickListener)
    document.removeEventListener("turbo:before-cache", this.beforeCacheListener)
  }

  handleToggle() {
    if (this.element.open) this.closeOtherMenus()
    this.syncSummaryState()
  }

  closeWhenOutside(event) {
    if (this.element.open && !this.element.contains(event.target)) {
      this.close({ restoreFocus: false })
    }
  }

  closeWhenFocusMovesOutside(event) {
    if (this.element.open && !this.element.contains(event.target)) {
      this.close({ restoreFocus: false })
    }
  }

  closeOnEscape(event) {
    if (event.key !== "Escape" || !this.element.open) return

    event.preventDefault()
    this.close()
  }

  closeAfterSelection(event) {
    if (!this.element.open || !this.element.contains(event.target)) return

    const target = event.target?.closest?.("a, button")
    if (!target || target === this.summary || !this.element.contains(target)) return

    this.close({ restoreFocus: false })
  }

  closeOtherMenus() {
    document.querySelectorAll(MENU_SELECTOR).forEach((menu) => {
      if (menu !== this.element && menu.open) menu.open = false
    })
  }

  close({ restoreFocus = true } = {}) {
    if (!this.element.open) {
      this.syncSummaryState()
      return
    }

    this.element.open = false
    this.syncSummaryState()

    if (restoreFocus) this.summary?.focus()
  }

  syncSummaryState() {
    this.summary?.setAttribute("aria-expanded", this.element.open.toString())
  }
}
