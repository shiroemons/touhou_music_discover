import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "toggle"]

  connect() {
    this.mobileQuery = window.matchMedia("(max-width: 991.98px)")
    this.mediaQueryListener = () => this.syncWithViewport()
    this.mobileQuery.addEventListener("change", this.mediaQueryListener)
    this.syncWithViewport()
  }

  disconnect() {
    this.mobileQuery?.removeEventListener("change", this.mediaQueryListener)
  }

  toggle() {
    this.setOpen(this.menuTarget.classList.contains("is-collapsed"))
  }

  syncWithViewport() {
    this.setOpen(!this.mobileQuery.matches)
  }

  setOpen(open) {
    const isMobile = this.mobileQuery?.matches
    const shouldOpen = !isMobile || open

    this.menuTarget.classList.toggle("is-collapsed", !shouldOpen)
    this.menuTarget.classList.toggle("is-open", shouldOpen)
    this.toggleTarget.setAttribute("aria-expanded", shouldOpen.toString())
  }
}
