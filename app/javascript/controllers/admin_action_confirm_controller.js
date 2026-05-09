import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  connect() {
    this.confirmed = false
  }

  submit(event) {
    if (this.confirmed) {
      return
    }

    event.preventDefault()
    this.modalTarget.showModal()
  }

  confirm() {
    this.confirmed = true
    this.modalTarget.close()
    this.element.requestSubmit()
  }

  cancel() {
    this.modalTarget.close()
  }
}
