import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["error"]

  static values = {
    url: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    this.fetching = false
    this.timer = null
    this.poll()
  }

  disconnect() {
    this.stopPolling()
  }

  poll() {
    if (this.timer) return

    this.timer = setInterval(() => {
      this.fetchProgress()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  async fetchProgress() {
    if (this.fetching) return

    this.fetching = true

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html'
        }
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)

        // 完了またはエラー時はポーリング停止
        const completedCard = document.querySelector('.success-card')
        const errorCard = document.querySelector('.message-card .error-icon')
        if (completedCard || (errorCard && document.querySelector('.card-title')?.textContent.includes('エラー'))) {
          this.stopPolling()
        }
      } else if (response.status === 401) {
        // セッション切れの場合はトップページへリダイレクト
        this.stopPolling()
        window.location.href = '/'
      } else {
        throw new Error(`Progress request failed: ${response.status}`)
      }
    } catch (error) {
      console.error('Progress fetch error:', error)
      this.stopPolling()
      this.showError()
    } finally {
      this.fetching = false
    }
  }

  retry() {
    if (this.fetching) return

    this.hideError()
    this.poll()
    return this.fetchProgress()
  }

  showError() {
    if (this.hasErrorTarget) {
      this.errorTarget.hidden = false
    }
  }

  hideError() {
    if (this.hasErrorTarget) {
      this.errorTarget.hidden = true
    }
  }
}
