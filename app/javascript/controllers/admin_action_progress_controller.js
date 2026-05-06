import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    this.fetchProgress()
    this.timer = setInterval(() => {
      this.fetchProgress()
    }, this.intervalValue)
  }

  disconnect() {
    this.stopPolling()
  }

  async fetchProgress() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          Accept: "text/vnd.turbo-stream.html"
        }
      })

      if (!response.ok) {
        return
      }

      const html = await response.text()
      Turbo.renderStreamMessage(html)

      const progressCard = document.querySelector("#admin-action-progress")
      if (progressCard?.dataset.status !== "processing") {
        this.stopPolling()
      }
    } catch (error) {
      console.error("Admin action progress fetch error:", error)
    }
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }
}
