import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hidden", "input", "listbox", "option"]
  static values = {
    url: String
  }

  connect() {
    this.activeIndex = -1
    this.selectedValue = this.hiddenTarget.value
    this.selectedLabel = this.inputTarget.value
    this.loadedQuery = null
    this.requestSequence = 0
    this.close()
  }

  disconnect() {
    clearTimeout(this.searchTimer)
  }

  filter() {
    this.open()
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => {
      this.loadOptions(this.inputTarget.value, { activateFirst: true })
    }, 150)
  }

  focus() {
    this.open()
    this.loadOptions("", { activateFirst: false })

    if (this.inputMatchesSelectedOption()) {
      this.inputTarget.select()
    }
  }

  open() {
    this.listboxTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.listboxTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
  }

  choose(event) {
    event.preventDefault()
    this.selectOption(event.currentTarget)
  }

  keydown(event) {
    const visibleOptions = this.visibleOptions()

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.open()
      this.activeIndex = Math.min(this.activeIndex + 1, visibleOptions.length - 1)
      this.updateActiveOption()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.open()
      this.activeIndex = Math.max(this.activeIndex - 1, 0)
      this.updateActiveOption()
    } else if (event.key === "Enter" && this.activeIndex >= 0) {
      event.preventDefault()
      this.selectOption(visibleOptions[this.activeIndex])
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  blur() {
    setTimeout(() => {
      this.restoreSelectedLabel()
      this.close()
    }, 120)
  }

  selectOption(option) {
    if (!option) return

    this.hiddenTarget.value = option.dataset.value
    this.inputTarget.value = option.dataset.label
    this.selectedValue = option.dataset.value
    this.selectedLabel = option.dataset.label
    this.close()
  }

  inputMatchesSelectedOption() {
    return this.selectedValue !== "" && this.inputTarget.value === this.selectedLabel
  }

  restoreSelectedLabel() {
    this.inputTarget.value = this.selectedLabel
  }

  visibleOptions() {
    return this.optionTargets.filter((option) => !option.hidden)
  }

  async loadOptions(query, { activateFirst }) {
    if (!this.hasUrlValue || this.loadedQuery === query) {
      this.activeIndex = activateFirst && this.visibleOptions().length > 0 ? 0 : -1
      this.updateActiveOption()
      return
    }

    const requestId = this.requestSequence + 1
    this.requestSequence = requestId
    this.listboxTarget.setAttribute("aria-busy", "true")

    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("q", query)
      if (this.selectedValue !== "") {
        url.searchParams.set("selected", this.selectedValue)
      }

      const response = await fetch(url.toString(), {
        headers: {
          Accept: "application/json"
        }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      if (requestId !== this.requestSequence) return

      const data = await response.json()
      this.loadedQuery = query
      this.renderOptions(data.options || [], { activateFirst })
    } catch (_error) {
      if (requestId === this.requestSequence) {
        this.renderOptions([], { activateFirst: false })
      }
    } finally {
      if (requestId === this.requestSequence) {
        this.listboxTarget.removeAttribute("aria-busy")
      }
    }
  }

  renderOptions(options, { activateFirst }) {
    this.listboxTarget.replaceChildren(...options.map((option) => this.buildOption(option)))
    this.activeIndex = activateFirst && options.length > 0 ? 0 : -1
    this.updateActiveOption()
  }

  buildOption(option) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "admin-association-option"
    button.setAttribute("role", "option")
    button.setAttribute("aria-selected", "false")
    button.setAttribute("data-admin-association-select-target", "option")
    button.setAttribute("data-action", "mousedown->admin-association-select#choose")
    button.dataset.value = option.value
    button.dataset.label = option.label
    button.textContent = option.label
    return button
  }

  updateActiveOption() {
    const visibleOptions = this.visibleOptions()

    this.optionTargets.forEach((option) => {
      option.classList.remove("is-active")
      option.setAttribute("aria-selected", "false")
    })

    const activeOption = visibleOptions[this.activeIndex]
    if (!activeOption) return

    activeOption.classList.add("is-active")
    activeOption.setAttribute("aria-selected", "true")
    activeOption.scrollIntoView({ block: "nearest" })
  }
}
