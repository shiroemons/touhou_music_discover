import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 1000 }
  }

  connect() {
    this.poll()
  }

  disconnect() {
    this.stopPolling()
  }

  poll() {
    this.timer = setInterval(() => {
      this.fetchRefreshCounts()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  async fetchRefreshCounts() {
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
        const completedCard = document.querySelector('.refresh-counts-completed')
        const errorCard = document.querySelector('.refresh-counts-error')
        if (completedCard || errorCard) {
          this.stopPolling()
        }
      } else if (response.status === 401) {
        // セッション切れの場合はトップページへリダイレクト
        window.location.href = '/'
      }
    } catch (error) {
      console.error('Refresh counts fetch error:', error)
    }
  }
}
