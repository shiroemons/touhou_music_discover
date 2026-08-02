import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "status", "retry"]
  static values = {
    url: String,
    loadingText: { type: String, default: "読み込み中..." },
    errorText: { type: String, default: "楽曲の読み込みに失敗しました。" },
    retryText: { type: String, default: "再試行" }
  }

  connect() {
    this.loaded = false
    this.loading = false
  }

  toggle() {
    if (!this.element.open || this.loaded || this.loading) return

    this.loadTracks()
  }

  retry(event) {
    event.preventDefault()
    this.loadTracks()
  }

  async loadTracks() {
    if (!this.hasUrlValue || this.loading) return

    this.loading = true
    this.statusTarget.textContent = this.loadingTextValue
    this.statusTarget.hidden = false
    this.retryTarget.hidden = true
    this.contentTarget.hidden = true
    this.contentTarget.setAttribute("aria-busy", "true")

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this.contentTarget.innerHTML = await response.text()
      this.contentTarget.hidden = false
      this.loaded = true
      this.statusTarget.hidden = true
    } catch (_error) {
      this.statusTarget.textContent = this.errorTextValue
      this.statusTarget.hidden = false
      this.retryTarget.textContent = this.retryTextValue
      this.retryTarget.hidden = false
    } finally {
      this.loading = false
      this.contentTarget.removeAttribute("aria-busy")
    }
  }
}
