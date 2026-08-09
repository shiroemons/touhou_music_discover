import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "rows", "sentinel", "status", "retry"]
  static values = {
    enabled: Boolean,
    nextUrl: String
  }

  connect() {
    if (!this.enabledValue || !this.hasSentinelTarget || !this.nextUrlValue) return

    this.loading = false
    this.paused = false
    this.abortController = null
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
    this.abortController?.abort()
  }

  retry() {
    if (this.loading || !this.nextUrlValue) return

    this.paused = false
    this.hideRetry()
    this.loadNextPage()
  }

  async loadNextPage() {
    if (this.loading || this.paused || !this.nextUrlValue) return

    this.loading = true
    this.hideRetry()
    this.setStatus(this.statusText("loadingText", "読み込み中..."))
    const abortController = new AbortController()
    this.abortController = abortController

    try {
      const response = await fetch(this.nextUrlValue, {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        signal: abortController.signal
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const html = await response.text()
      const documentFragment = new DOMParser().parseFromString(html, "text/html")
      const incomingRows = documentFragment.querySelectorAll("[data-admin-infinite-scroll-target='rows'] > *")
      incomingRows.forEach((row) => this.rowsTarget.appendChild(row))

      const nextPanel = documentFragment.querySelector("[data-controller~='admin-infinite-scroll']")
      this.nextUrlValue = nextPanel?.dataset.adminInfiniteScrollNextUrlValue || ""

      if (this.nextUrlValue) {
        this.setStatus(this.statusText("readyText", "下までスクロールすると追加で読み込みます"))
      } else {
        this.finish()
      }
    } catch (error) {
      if (error?.name === "AbortError") return

      this.paused = true
      this.setStatus(this.statusText("errorText", "読み込みに失敗しました"))
      this.showRetry()
    } finally {
      if (this.abortController === abortController) this.abortController = null
      this.loading = false
    }
  }

  finish() {
    this.observer?.disconnect()
    if (this.hasSentinelTarget) this.sentinelTarget.remove()
    this.hideRetry()
    this.setStatus(this.statusText("completeText", "すべて読み込みました"))
  }

  statusText(name, fallback) {
    return this.hasStatusTarget ? this.statusTarget.dataset[name] || fallback : fallback
  }

  showRetry() {
    if (this.hasRetryTarget) this.retryTarget.hidden = false
  }

  hideRetry() {
    if (this.hasRetryTarget) this.retryTarget.hidden = true
  }

  setStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
  }
}
