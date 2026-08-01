import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hidden", "input", "listbox", "option", "selected"]
  static values = {
    url: String,
    submitOnSelect: Boolean,
    multiple: Boolean,
    inputName: String,
    removeLabel: String
  }

  connect() {
    this.activeIndex = -1
    this.selectedValues = this.hiddenTargets
      .map((input) => input.value)
      .filter((value) => value !== "")
      .filter((value, index, values) => values.indexOf(value) === index)
    this.selectedValue = this.selectedValues[0] || ""
    this.selectedLabel = this.inputTarget.value
    this.loadedQuery = null
    this.requestSequence = 0
    this.syncSelectedState()
    this.renderSelectedOptions()
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
    this.element.classList.add("is-open")
  }

  close() {
    this.listboxTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.element.classList.remove("is-open")
  }

  choose(event) {
    event.preventDefault()
    this.selectOption(event.currentTarget)
  }

  remove(event) {
    event.preventDefault()
    if (!this.multipleValue) return

    const value = event.currentTarget.dataset.value
    this.selectedValues = this.selectedValues.filter((selectedValue) => selectedValue !== value)
    this.syncHiddenInputs()
    this.renderSelectedOptions()
    this.syncSelectedState()
    this.inputTarget.focus()
    this.open()
    this.filterStaticOptions(this.inputTarget.value, { activateFirst: false })
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
      if (this.multipleValue) {
        this.inputTarget.value = ""
      } else {
        this.restoreSelectedLabel()
      }
      this.close()
    }, 120)
  }

  selectOption(option) {
    if (!option) return

    if (this.multipleValue) {
      this.toggleOption(option)
      return
    }

    this.hiddenTarget.value = option.dataset.value
    this.inputTarget.value = option.dataset.label
    this.selectedValue = option.dataset.value
    this.selectedValues = this.selectedValue === "" ? [] : [this.selectedValue]
    this.selectedLabel = option.dataset.label
    this.syncSelectedState()
    this.close()

    if (this.submitOnSelectValue) this.hiddenTarget.form?.requestSubmit()
  }

  toggleOption(option) {
    const value = option.dataset.value

    if (value === "") {
      this.selectedValues = []
    } else if (this.selectedValues.includes(value)) {
      this.selectedValues = this.selectedValues.filter((selectedValue) => selectedValue !== value)
    } else {
      this.selectedValues = [...this.selectedValues, value]
    }

    this.syncHiddenInputs()
    this.renderSelectedOptions()
    this.syncSelectedState()
    this.inputTarget.value = ""
    this.activeIndex = this.visibleOptions().indexOf(option)
    this.updateActiveOption()
  }

  inputMatchesSelectedOption() {
    if (this.multipleValue) return false

    return this.selectedValue !== "" && this.inputTarget.value === this.selectedLabel
  }

  restoreSelectedLabel() {
    this.inputTarget.value = this.selectedLabel
  }

  visibleOptions() {
    return this.optionTargets.filter((option) => (
      !option.hidden && !option.closest("[data-admin-association-select-option-group]")?.hidden
    ))
  }

  async loadOptions(query, { activateFirst }) {
    if (!this.hasUrlValue) {
      this.filterStaticOptions(query, { activateFirst })
      return
    }

    if (this.loadedQuery === query) {
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
      if (this.multipleValue) {
        this.selectedValues.forEach((value) => url.searchParams.append("selected[]", value))
      } else if (this.selectedValue !== "") {
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

  filterStaticOptions(query, { activateFirst }) {
    const normalizedQuery = query.trim().toLowerCase()

    this.optionTargets.forEach((option) => {
      const searchText = (option.dataset.searchText || option.dataset.label || option.textContent).toLowerCase()
      option.hidden = normalizedQuery !== "" && !searchText.includes(normalizedQuery)
    })

    this.updateOptionGroups()
    this.activeIndex = activateFirst && this.visibleOptions().length > 0 ? 0 : -1
    this.updateActiveOption()
  }

  renderOptions(options, { activateFirst }) {
    this.listboxTarget.replaceChildren(...options.map((option) => this.buildOption(option)))
    this.ensureOptionIds()
    this.syncSelectedState()
    this.activeIndex = activateFirst && this.visibleOptions().length > 0 ? 0 : -1
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

    this.optionTargets.forEach((option) => option.classList.remove("is-active"))
    this.syncSelectedState()

    const activeOption = visibleOptions[this.activeIndex]
    if (!activeOption) {
      this.inputTarget.removeAttribute("aria-activedescendant")
      return
    }

    this.ensureOptionIds()
    activeOption.classList.add("is-active")
    this.inputTarget.setAttribute("aria-activedescendant", activeOption.id)
    activeOption.scrollIntoView({ block: "nearest" })
  }

  syncSelectedState() {
    this.optionTargets.forEach((option) => {
      const selected = this.optionSelected(option)
      option.classList.toggle("is-selected", selected)
      option.setAttribute("aria-selected", selected.toString())
    })
  }

  optionSelected(option) {
    if (this.multipleValue) {
      return option.dataset.value === ""
        ? this.selectedValues.length === 0
        : this.selectedValues.includes(option.dataset.value)
    }

    return option.dataset.value === this.selectedValue
  }

  updateOptionGroups() {
    this.listboxTarget.querySelectorAll("[data-admin-association-select-option-group]").forEach((group) => {
      group.hidden = !Array.from(group.querySelectorAll('[role="option"]')).some((option) => !option.hidden)
    })
  }

  ensureOptionIds() {
    this.optionTargets.forEach((option, index) => {
      if (!option.id) option.id = `${this.inputTarget.id}-option-${index}`
    })
  }

  syncHiddenInputs() {
    if (!this.multipleValue) return

    const hiddenInputs = this.hiddenTargets.slice()
    const inputName = this.inputNameValue || hiddenInputs[0]?.name
    hiddenInputs.forEach((input) => input.remove())
    if (!inputName) return

    this.selectedValues.forEach((value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = inputName
      input.value = value
      input.dataset.adminAssociationSelectTarget = "hidden"
      this.element.prepend(input)
    })
  }

  renderSelectedOptions() {
    if (!this.hasSelectedTarget) return

    const selectedOptions = this.selectedValues.map((value) => (
      this.optionTargets.find((option) => option.dataset.value === value)
    )).filter(Boolean)

    this.selectedTarget.replaceChildren(...selectedOptions.map((option) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "admin-association-selection-chip"
      button.dataset.value = option.dataset.value
      button.dataset.action = "mousedown->admin-association-select#remove"
      button.setAttribute("aria-label", this.removeLabel(option.dataset.label))

      const label = document.createElement("span")
      label.textContent = option.dataset.label
      const close = document.createElement("span")
      close.textContent = "×"
      close.setAttribute("aria-hidden", "true")
      button.append(label, close)
      return button
    }))
  }

  removeLabel(label) {
    return (this.removeLabelValue || "%{label}").replace("%{label}", label)
  }
}
