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
        window.location.href = '/'
      }
    } catch (error) {
      console.error('Progress fetch error:', error)
    }
  }
}
