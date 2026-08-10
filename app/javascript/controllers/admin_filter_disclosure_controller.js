import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.mobileQuery = window.matchMedia("(max-width: 767.98px)")
    this.userToggled = false
    this.mediaQueryListener = () => {
      this.userToggled = false
      this.syncWithViewport()
    }
    this.summary = this.element.querySelector("summary")
    this.summaryClickListener = () => {
      if (this.mobileQuery.matches) this.userToggled = true
    }

    this.mobileQuery.addEventListener("change", this.mediaQueryListener)
    this.summary?.addEventListener("click", this.summaryClickListener)
    this.syncWithViewport()
  }

  disconnect() {
    this.mobileQuery?.removeEventListener("change", this.mediaQueryListener)
    this.summary?.removeEventListener("click", this.summaryClickListener)
  }

  syncWithViewport() {
    this.element.open = !this.mobileQuery.matches || this.userToggled
  }
}
