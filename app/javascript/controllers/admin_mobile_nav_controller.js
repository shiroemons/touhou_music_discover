import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "open", "close", "backdrop"]

  connect() {
    this.mobileQuery = window.matchMedia("(max-width: 991.98px)")
    this.mediaQueryListener = () => this.syncWithViewport()
    this.keydownListener = (event) => {
      if (event.key === "Escape" && this.isOpen() && this.mobileQuery.matches) {
        this.close()
      }
    }

    this.mobileQuery.addEventListener("change", this.mediaQueryListener)
    this.element.addEventListener("keydown", this.keydownListener)
    this.syncWithViewport()
  }

  disconnect() {
    this.mobileQuery?.removeEventListener("change", this.mediaQueryListener)
    this.element.removeEventListener("keydown", this.keydownListener)
    this.setBodyScrollLock(false)
  }

  open() {
    this.setOpen(true, { focusClose: true })
  }

  close() {
    this.setOpen(false, { restoreFocus: true })
  }

  toggle() {
    this.setOpen(!this.isOpen())
  }

  syncWithViewport() {
    this.setOpen(!this.mobileQuery.matches)
  }

  isOpen() {
    return this.drawerTarget.classList.contains("is-open")
  }

  setOpen(open, { focusClose = false, restoreFocus = false } = {}) {
    const isMobile = this.mobileQuery?.matches
    const shouldOpen = !isMobile || open
    const wasOpen = this.isOpen()

    this.drawerTarget.classList.toggle("is-open", shouldOpen)
    this.drawerTarget.setAttribute("aria-hidden", (!shouldOpen).toString())
    this.drawerTarget.inert = Boolean(isMobile && !shouldOpen)
    this.backdropTarget.hidden = !(isMobile && shouldOpen)
    this.backdropTarget.classList.toggle("is-visible", Boolean(isMobile && shouldOpen))
    this.openTarget.setAttribute("aria-expanded", shouldOpen.toString())
    this.setBodyScrollLock(Boolean(isMobile && shouldOpen))

    if (focusClose && isMobile && shouldOpen) {
      this.closeTarget.focus()
    } else if (restoreFocus && wasOpen && isMobile && !shouldOpen) {
      this.openTarget.focus()
    }
  }

  setBodyScrollLock(locked) {
    if (typeof document !== "undefined") {
      document.body.classList.toggle("admin-mobile-nav-open", locked)
    }
  }
}
