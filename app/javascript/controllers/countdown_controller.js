import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["seconds", "clock"]
  static values = {
    expiresAt: Number,
    expiredText: String
  }

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    this.stop()
  }

  tick() {
    const remainingSeconds = this.remainingSeconds()

    if (this.hasSecondsTarget) {
      this.secondsTarget.textContent = remainingSeconds > 0 ? this.formatReadableDuration(remainingSeconds) : this.expiredTextValue
    }

    if (this.hasClockTarget) {
      this.clockTarget.textContent = remainingSeconds > 0 ? `(${this.formatDuration(remainingSeconds)})` : ""
    }

    if (remainingSeconds <= 0) {
      this.element.classList.add("is-expired")
      this.stop()
    }
  }

  remainingSeconds() {
    const expiresAtMilliseconds = this.expiresAtValue * 1000
    return Math.max(0, Math.ceil((expiresAtMilliseconds - Date.now()) / 1000))
  }

  formatDuration(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    return [hours, minutes, seconds]
      .map((value) => value.toString().padStart(2, "0"))
      .join(":")
  }

  formatReadableDuration(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    const parts = []

    if (hours > 0) {
      parts.push(`${hours}時間`)
    }

    if (minutes > 0) {
      parts.push(`${minutes}分`)
    }

    if (seconds > 0 || parts.length === 0) {
      parts.push(`${seconds}秒`)
    }

    return parts.join("")
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }
}
