import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "open", "openLabel", "close", "backdrop"]
  static values = {
    mobileLabel: String,
    mobileCloseLabel: String,
    desktopOpenLabel: String,
    desktopCloseLabel: String
  }

  connect() {
    this.desktopOpen = true
    this.mobileQuery = window.matchMedia("(max-width: 991.98px)")
    this.mediaQueryListener = () => this.syncWithViewport()
    this.keydownListener = (event) => {
      if (event.key === "Escape" && this.isOpen()) {
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
    const shouldOpen = !this.isOpen()
    this.setOpen(shouldOpen, {
      focusClose: shouldOpen,
      restoreFocus: !shouldOpen
    })
  }

  syncWithViewport() {
    const shouldOpen = this.mobileQuery.matches ? false : this.desktopOpen
    this.setOpen(shouldOpen)
  }

  isOpen() {
    return this.drawerTarget.classList.contains("is-open")
  }

  setOpen(open, { focusClose = false, restoreFocus = false } = {}) {
    const isMobile = Boolean(this.mobileQuery?.matches)
    const shouldOpen = Boolean(open)
    const wasOpen = this.isOpen()

    if (!isMobile) {
      this.desktopOpen = shouldOpen
    }

    this.drawerTarget.classList.toggle("is-open", shouldOpen)
    this.element?.classList?.toggle("is-sidebar-collapsed", !shouldOpen)
    this.drawerTarget.setAttribute("aria-hidden", (!shouldOpen).toString())
    this.drawerTarget.inert = !shouldOpen
    this.backdropTarget.hidden = !(isMobile && shouldOpen)
    this.backdropTarget.classList.toggle("is-visible", Boolean(isMobile && shouldOpen))
    this.updateLabels({ isMobile, shouldOpen })
    this.setBodyScrollLock(Boolean(isMobile && shouldOpen))

    if (focusClose && shouldOpen) {
      this.closeTarget.focus()
    } else if (restoreFocus && wasOpen && !shouldOpen) {
      this.openTarget.focus()
    }
  }

  updateLabels({ isMobile, shouldOpen }) {
    const toggleLabel = isMobile
      ? (shouldOpen ? this.mobileCloseLabelValue : this.mobileLabelValue)
      : (shouldOpen ? this.desktopCloseLabelValue : this.desktopOpenLabelValue)
    const closeLabel = isMobile ? this.mobileCloseLabelValue : this.desktopCloseLabelValue

    this.openTarget.setAttribute("aria-expanded", shouldOpen.toString())
    this.openTarget.setAttribute("aria-label", toggleLabel)
    if (this.openLabelTarget) {
      this.openLabelTarget.textContent = toggleLabel
    }
    if (this.closeTarget) {
      this.closeTarget.setAttribute("aria-label", closeLabel)
    }
  }

  setBodyScrollLock(locked) {
    if (typeof document !== "undefined") {
      document.body.classList.toggle("admin-mobile-nav-open", locked)
    }
  }
}
