import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "rows", "sentinel", "status"]
  static values = {
    enabled: Boolean,
    nextUrl: String
  }

  connect() {
    if (!this.enabledValue || !this.hasSentinelTarget || !this.nextUrlValue) return

    this.loading = false
    this.observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) this.loadNextPage()
    }, {
      root: this.hasContainerTarget ? this.containerTarget : null,
      rootMargin: "240px 0px"
    })
    this.observer.observe(this.sentinelTarget)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  async loadNextPage() {
    if (this.loading || !this.nextUrlValue) return

    this.loading = true
    this.setStatus(this.statusTarget.dataset.loadingText || "読み込み中...")

    try {
      const response = await fetch(this.nextUrlValue, {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const html = await response.text()
      const documentFragment = new DOMParser().parseFromString(html, "text/html")
      const incomingRows = documentFragment.querySelectorAll("[data-admin-infinite-scroll-target='rows'] tr")
      incomingRows.forEach((row) => this.rowsTarget.appendChild(row))

      const nextPanel = documentFragment.querySelector("[data-controller~='admin-infinite-scroll']")
      this.nextUrlValue = nextPanel?.dataset.adminInfiniteScrollNextUrlValue || ""

      if (this.nextUrlValue) {
        this.setStatus(this.statusTarget.dataset.readyText || "下までスクロールすると追加で読み込みます")
      } else {
        this.finish()
      }
    } catch (_error) {
      this.setStatus(this.statusTarget.dataset.errorText || "読み込みに失敗しました")
    } finally {
      this.loading = false
    }
  }

  finish() {
    this.observer?.disconnect()
    this.sentinelTarget?.remove()
    this.setStatus(this.statusTarget.dataset.completeText || "すべて読み込みました")
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
  }
}
