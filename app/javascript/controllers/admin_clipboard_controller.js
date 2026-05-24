import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "status"]

  async copy() {
    const text = this.sourceTarget.value
    if (!text) return

    try {
      await this.writeText(text)
      this.showStatus("コピーしました")
    } catch (_error) {
      this.showStatus("コピーできませんでした")
    }
  }

  async writeText(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return
    }

    this.sourceTarget.hidden = false
    this.sourceTarget.focus()
    this.sourceTarget.select()
    document.execCommand("copy")
    this.sourceTarget.hidden = true
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    clearTimeout(this.statusTimer)
    this.statusTimer = setTimeout(() => {
      this.statusTarget.textContent = ""
    }, 2500)
  }
}
