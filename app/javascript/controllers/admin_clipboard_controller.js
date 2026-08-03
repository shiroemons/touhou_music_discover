import { Controller } from "@hotwired/stimulus"
import { showAdminToast } from "./admin_toast_controller.mjs"

export default class extends Controller {
  static targets = ["source"]
  static values = {
    text: String,
    successMessage: { type: String, default: "コピーしました" },
    failureMessage: { type: String, default: "コピーできませんでした" }
  }

  async copy(event) {
    event?.preventDefault()
    if (event?.currentTarget?.closest("summary")) event.stopPropagation()
    const text = this.textFor(event)
    if (!text) return

    try {
      await this.writeText(text)
      showAdminToast(this.successMessageValue, { variant: "success" })
    } catch (_error) {
      showAdminToast(this.failureMessageValue, { variant: "error" })
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

}
