import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["error", "retry"]
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

  retry() {
    if (this.fetching) return

    this.polling = true
    this.hideFetchError()
    this.fetchProgress()
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

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const html = await response.text()
      this.hideFetchError()
      Turbo.renderStreamMessage(html)

      if (response.headers.get("X-Admin-Action-Polling") === "false") {
        this.stopPolling()
      }
    } catch (error) {
      console.error("Admin action progress fetch error:", error)
      this.stopPolling()
      this.showFetchError()
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

  showFetchError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = false
    if (this.hasRetryTarget) this.retryTarget.hidden = false
  }

  hideFetchError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = true
    if (this.hasRetryTarget) this.retryTarget.hidden = true
  }
}
