import { Controller } from "@hotwired/stimulus"
import { Modal } from "bootstrap"

export default class extends Controller {
  static targets = ["modal"]

  connect() {
    this.confirmed = false
  }

  disconnect() {
    this.modalInstance?.dispose()
  }

  submit(event) {
    if (this.confirmed) {
      return
    }

    event.preventDefault()
    this.modal.show()
  }

  confirm() {
    this.confirmed = true
    this.modal.hide()
    this.element.requestSubmit()
  }

  get modal() {
    this.modalInstance ||= new Modal(this.modalTarget)
    return this.modalInstance
  }
}
