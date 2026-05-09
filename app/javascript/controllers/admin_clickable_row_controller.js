import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    href: String
  }

  open(event) {
    if (event.defaultPrevented || event.target.closest("a, button, input, select, textarea")) return

    Turbo.visit(this.hrefValue)
  }
}
