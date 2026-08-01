import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "status"]
  static values = {
    text: String
  }

  async copy(event) {
    event?.preventDefault()
    const text = this.textFor(event)
    if (!text) return

    try {
      await this.writeText(text)
      this.showStatus("コピーしました")
    } catch (_error) {
      this.showStatus("コピーできませんでした")
    }
  }

  textFor(event) {
    const eventText = event?.currentTarget?.dataset?.adminClipboardTextValue
    if (eventText !== undefined) return eventText
    if (this.hasTextValue) return this.textValue
    return this.hasSourceTarget ? this.sourceTarget.value : ""
  }

  async writeText(text) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text)
      return
    }

    const hasSource = this.hasSourceTarget
    const source = hasSource ? this.sourceTarget : document.createElement("textarea")
    const previousHidden = source.hidden

    try {
      if (!hasSource) {
        source.value = text
        source.setAttribute("readonly", "")
        source.style.opacity = "0"
        source.style.position = "fixed"
        document.body.append(source)
      }

      source.hidden = false
      source.focus()
      source.select()
      if (!document.execCommand("copy")) throw new Error("Clipboard copy command failed")
    } finally {
      if (hasSource) {
        source.hidden = previousHidden
      } else {
        source.remove()
      }
    }
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
