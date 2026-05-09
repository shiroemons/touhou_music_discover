import { Controller } from "@hotwired/stimulus"

const THEMES = ["light", "dark", "system"]

export default class extends Controller {
  static targets = ["button"]
  static values = {
    storageKey: { type: String, default: "touhou-admin-theme" }
  }

  connect() {
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQueryListener = () => {
      if (this.currentTheme() === "system") {
        this.applyTheme("system", { persist: false })
      }
    }

    this.mediaQuery.addEventListener("change", this.mediaQueryListener)
    this.applyTheme(this.currentTheme(), { persist: false })
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.mediaQueryListener)
  }

  set(event) {
    this.applyTheme(event.currentTarget.dataset.adminThemeMode, { persist: true })
  }

  currentTheme() {
    const theme = this.readStoredTheme() || document.documentElement.dataset.adminTheme || "system"
    return THEMES.includes(theme) ? theme : "system"
  }

  readStoredTheme() {
    try {
      return localStorage.getItem(this.storageKeyValue)
    } catch (_error) {
      return null
    }
  }

  writeStoredTheme(theme) {
    try {
      localStorage.setItem(this.storageKeyValue, theme)
    } catch (_error) {
      // Storage can be unavailable in strict browser modes; the DOM state still updates.
    }
  }

  applyTheme(theme, { persist }) {
    const selectedTheme = THEMES.includes(theme) ? theme : "system"
    const resolvedTheme = selectedTheme === "system" ? this.systemTheme() : selectedTheme
    const root = document.documentElement

    root.dataset.adminTheme = selectedTheme
    root.dataset.adminResolvedTheme = resolvedTheme
    root.dataset.theme = resolvedTheme

    if (persist) {
      this.writeStoredTheme(selectedTheme)
    }

    this.updateButtons(selectedTheme)
  }

  systemTheme() {
    return this.mediaQuery?.matches ? "dark" : "light"
  }

  updateButtons(selectedTheme) {
    this.buttonTargets.forEach((button) => {
      const active = button.dataset.adminThemeMode === selectedTheme
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", active.toString())
    })
  }
}
