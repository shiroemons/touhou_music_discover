import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    this.polling = true
    this.fetchProgress()
  }

  disconnect() {
    this.stopPolling()
  }

  async fetchProgress() {
    if (!this.polling || this.fetching) {
      return
    }

    this.fetching = true

    try {
      const response = await fetch(this.urlValue, {
        cache: "no-store",
        headers: {
          Accept: "text/vnd.turbo-stream.html"
        }
      })

      if (!response.ok) {
        return
      }

      const html = await response.text()
      Turbo.renderStreamMessage(html)

      if (response.headers.get("X-Admin-Action-Polling") === "false") {
        this.stopPolling()
      }
    } catch (error) {
      console.error("Admin action progress fetch error:", error)
    } finally {
      this.fetching = false
      this.scheduleNext()
    }
  }

  scheduleNext() {
    if (!this.polling || this.timer) {
      return
    }

    this.timer = setTimeout(() => {
      this.timer = null
      this.fetchProgress()
    }, this.intervalValue)
  }

  stopPolling() {
    this.polling = false

    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }
}
