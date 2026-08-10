import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  connect() {
    this.confirmed = false
    this.returnFocusElement = null
    this.handleModalClose = () => {
      if (this.confirmed) return

      const returnFocusElement = this.returnFocusElement
      this.returnFocusElement = null
      returnFocusElement?.focus?.({ preventScroll: true })
    }
    this.modalTarget.addEventListener?.("close", this.handleModalClose)
  }

  disconnect() {
    if (this.hasModalTarget) {
      this.modalTarget.removeEventListener?.("close", this.handleModalClose)
    }
  }

  submit(event) {
    if (this.confirmed) {
      return
    }

    event.preventDefault()
    this.returnFocusElement = document.activeElement
    this.modalTarget.showModal()
  }

  confirm() {
    if (this.confirmed) {
      return
    }

    this.confirmed = true
    this.element.setAttribute('aria-busy', 'true')
    this.element.querySelectorAll('button').forEach((button) => {
      button.disabled = true
    })
    this.modalTarget.close()
    this.element.requestSubmit()
  }

  cancel() {
    this.modalTarget.close()
  }
}
