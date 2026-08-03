import { Controller } from "@hotwired/stimulus"

const PASTED_ORIGINAL_SONG_DELIMITER_PATTERN = /[,、，\/／]/

export default class extends Controller {
  static targets = ["hidden", "input", "listbox", "selected"]
  static values = {
    url: String,
    resolveUrl: String,
    initialOptions: Array
  }

  connect() {
    this.selectedOptions = this.hasInitialOptionsValue ? [...this.initialOptionsValue] : []
    this.activeIndex = -1
    this.loadedQuery = null
    this.requestSequence = 0
    this.resolveRowPasteHandler = (event) => this.resolvePastedRow(event)
    this.element.addEventListener("admin-original-song-picker:resolve-row", this.resolveRowPasteHandler)
    this.renderSelectedOptions()
    this.syncHiddenValue()
    this.close()
  }

  disconnect() {
    clearTimeout(this.searchTimer)
    clearTimeout(this.missingQueryTimer)
    this.element.removeEventListener("admin-original-song-picker:resolve-row", this.resolveRowPasteHandler)
  }

  focus() {
    this.open()
    this.loadOptions(this.inputTarget.value, { activateFirst: false })
  }

  filter() {
    this.open()
    clearTimeout(this.searchTimer)
    this.searchTimer = setTimeout(() => {
      this.loadOptions(this.inputTarget.value, { activateFirst: true })
    }, 150)
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
      if (this.element.contains(document.activeElement)) return

      this.close()
    }, 120)
  }

  choose(event) {
    event.preventDefault()
    this.selectOption(event.currentTarget)
  }

  retryMissingQuery(event) {
    event.preventDefault()
    const input = this.missingQueryInputFor(event.currentTarget)
    if (!input) return

    this.resolveEditedMissingQuery(input, { preserveMissingOnEmpty: false })
  }

  keydownMissingQuery(event) {
    if (event.key === "Enter") {
      this.retryMissingQuery(event)
    } else if (event.key === "Escape") {
      this.close()
      this.inputTarget.focus()
    }
  }

  filterMissingQuery(event) {
    const input = event.currentTarget
    clearTimeout(this.missingQueryTimer)
    this.missingQueryTimer = setTimeout(() => {
      this.resolveEditedMissingQuery(input, { preserveMissingOnEmpty: true })
    }, 250)
  }

  paste(event) {
    const text = event.clipboardData?.getData("text")
    if (!text || !this.hasResolveUrlValue) return

    event.preventDefault()
    const rows = this.pastedRows(text)
    if (rows.length > 1) {
      const pastedText = rows.join("\n")
      if (this.shouldDistributePastedRows(rows, event)) {
        this.resolvePastedRows(pastedText)
      } else {
        this.resolvePastedText(pastedText)
      }
    } else {
      this.resolvePastedText(rows[0] || text.trim())
    }
  }

  resolvePastedRow(event) {
    event.preventDefault()
    const text = event.detail?.text?.trim()
    if (!text) return

    this.resolvePastedText(text)
  }

  remove(event) {
    event.preventDefault()
    const value = event.currentTarget.dataset.value
    this.selectedOptions = this.selectedOptions.filter((option) => option.value !== value)
    this.renderSelectedOptions()
    this.syncHiddenValue()
    this.renderOptions(this.currentOptions || [], { activateFirst: false })
  }

  open() {
    this.listboxTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.listboxTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.activeIndex = -1
    this.updateActiveOption()
  }

  shouldDistributePastedRows(rows, event) {
    return event.shiftKey || rows.some((row) => PASTED_ORIGINAL_SONG_DELIMITER_PATTERN.test(row))
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

      const response = await fetch(url.toString(), {
        headers: {
          Accept: "application/json"
        }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      if (requestId !== this.requestSequence) return

      const data = await response.json()
      this.loadedQuery = query
      this.currentOptions = data.options || []
      this.renderOptions(this.currentOptions, { activateFirst })
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

  async resolvePastedText(text) {
    const requestId = this.requestSequence + 1
    this.requestSequence = requestId
    this.open()
    this.listboxTarget.setAttribute("aria-busy", "true")

    try {
      const url = new URL(this.resolveUrlValue, window.location.origin)
      url.searchParams.set("text", text)

      const response = await fetch(url.toString(), {
        headers: {
          Accept: "application/json"
        }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      if (requestId !== this.requestSequence) return

      const data = await response.json()
      this.inputTarget.value = ""
      this.loadedQuery = null
      this.renderResolvedOptions(data.resolutions || [])
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

  async resolveEditedMissingQuery(input, { preserveMissingOnEmpty }) {
    const query = input.value.trim()
    if (!query) return

    const requestId = this.requestSequence + 1
    this.requestSequence = requestId
    this.open()
    this.listboxTarget.setAttribute("aria-busy", "true")

    try {
      const url = new URL(this.resolveUrlValue, window.location.origin)
      url.searchParams.set("text", query)

      const response = await fetch(url.toString(), {
        headers: {
          Accept: "application/json"
        }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      if (requestId !== this.requestSequence) return

      const data = await response.json()
      const resolutions = data.resolutions || []
      const hasOptions = resolutions.some((resolution) => (resolution.options || []).length > 0)
      if (preserveMissingOnEmpty && !hasOptions) return

      this.inputTarget.value = ""
      this.loadedQuery = null
      this.renderResolvedOptions(resolutions)
    } catch (_error) {
      if (!preserveMissingOnEmpty && requestId === this.requestSequence) {
        this.renderOptions([], { activateFirst: false })
      }
    } finally {
      if (requestId === this.requestSequence) {
        this.listboxTarget.removeAttribute("aria-busy")
      }
    }
  }

  selectOption(optionElement) {
    if (!optionElement) return

    this.addOption({
      value: optionElement.dataset.value,
      label: optionElement.dataset.label
    })

    this.inputTarget.value = ""
    this.loadedQuery = null
    this.renderSelectedOptions()
    this.syncHiddenValue()
    this.renderOptions(this.currentOptions || [], { activateFirst: false })
    this.inputTarget.focus()
  }

  addOption(option) {
    if (!option?.value || this.selectedOptions.some((selectedOption) => selectedOption.value === option.value)) return

    this.selectedOptions = [...this.selectedOptions, option]
  }

  renderSelectedOptions() {
    if (this.selectedOptions.length === 0) {
      const empty = document.createElement("span")
      empty.className = "admin-original-song-empty-selection"
      empty.textContent = "未設定"
      this.selectedTarget.replaceChildren(empty)
      return
    }

    this.selectedTarget.replaceChildren(...this.selectedOptions.map((option) => this.buildSelectedOption(option)))
  }

  buildSelectedOption(option) {
    const chip = document.createElement("span")
    chip.className = "admin-original-song-chip"

    const label = document.createElement("span")
    label.textContent = option.label

    const button = document.createElement("button")
    button.type = "button"
    button.className = "admin-original-song-chip-remove"
    button.dataset.value = option.value
    button.dataset.action = "admin-original-song-picker#remove"
    button.setAttribute("aria-label", `${option.label}を削除`)
    button.textContent = "×"

    chip.append(label, button)
    return chip
  }

  renderOptions(options, { activateFirst }) {
    const availableOptions = options.filter((option) => (
      !this.selectedOptions.some((selectedOption) => selectedOption.value === option.value)
    ))

    if (availableOptions.length === 0) {
      const empty = document.createElement("div")
      empty.className = "admin-original-song-option-empty"
      empty.textContent = "候補がありません"
      this.listboxTarget.replaceChildren(empty)
      this.activeIndex = -1
      return
    }

    this.listboxTarget.replaceChildren(...availableOptions.map((option) => this.buildOption(option)))
    this.activeIndex = activateFirst ? 0 : -1
    this.updateActiveOption()
  }

  renderResolvedOptions(resolutions) {
    const ambiguousOptions = []
    const missingQueries = []

    resolutions.forEach((resolution) => {
      const options = resolution.options || []

      if (options.length === 1) {
        this.addOption(options[0])
      } else if (options.length > 1) {
        options.forEach((option) => {
          ambiguousOptions.push({ ...option, groupLabel: resolution.query })
        })
      } else {
        missingQueries.push(resolution.query)
      }
    })

    this.renderSelectedOptions()
    this.syncHiddenValue()

    if (ambiguousOptions.length > 0 || missingQueries.length > 0) {
      this.renderResolvedChoiceList(ambiguousOptions, missingQueries)
      return
    }

    this.close()
  }

  renderResolvedChoiceList(options, missingQueries) {
    const availableOptions = options.filter((option) => (
      !this.selectedOptions.some((selectedOption) => selectedOption.value === option.value)
    ))
    const optionElements = availableOptions.map((option) => this.buildOption(option))
    const missingQueryElements = missingQueries.map((query) => this.buildMissingQuery(query))

    this.currentOptions = options
    this.listboxTarget.replaceChildren(...optionElements, ...missingQueryElements)
    this.activeIndex = optionElements.length > 0 ? 0 : -1
    this.updateActiveOption()
  }

  buildMissingQuery(query) {
    const container = document.createElement("div")
    container.className = "admin-original-song-missing-query"

    const label = document.createElement("label")
    label.className = "admin-original-song-missing-label"
    label.textContent = "候補が見つかりません"

    const controls = document.createElement("div")
    controls.className = "admin-original-song-missing-controls"

    const input = document.createElement("input")
    input.type = "search"
    input.className = "input admin-input admin-original-song-missing-input"
    input.value = query
    input.setAttribute("aria-label", "候補が見つからなかった原曲名を修正")
    input.dataset.action = [
      "input->admin-original-song-picker#filterMissingQuery",
      "keydown->admin-original-song-picker#keydownMissingQuery"
    ].join(" ")

    const button = document.createElement("button")
    button.type = "button"
    button.className = "admin-original-song-missing-button"
    button.dataset.action = "click->admin-original-song-picker#retryMissingQuery"
    button.textContent = "候補検索"

    controls.append(input, button)
    container.append(label, controls)
    return container
  }

  buildOption(option) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "admin-original-song-option"
    button.setAttribute("role", "option")
    button.setAttribute("aria-selected", "false")
    button.setAttribute("data-admin-original-song-picker-target", "option")
    button.setAttribute("data-action", "mousedown->admin-original-song-picker#choose")
    button.dataset.value = option.value
    button.dataset.label = option.label
    if (option.groupLabel) {
      const query = document.createElement("span")
      query.className = "admin-original-song-option-query"
      query.textContent = option.groupLabel

      const label = document.createElement("span")
      label.textContent = option.label
      button.append(query, label)
    } else {
      button.textContent = option.label
    }
    return button
  }

  updateActiveOption() {
    const visibleOptions = this.visibleOptions()

    visibleOptions.forEach((option) => {
      option.classList.remove("is-active")
      option.setAttribute("aria-selected", "false")
    })

    const activeOption = visibleOptions[this.activeIndex]
    if (!activeOption) return

    activeOption.classList.add("is-active")
    activeOption.setAttribute("aria-selected", "true")
    activeOption.scrollIntoView({ block: "nearest" })
  }

  visibleOptions() {
    return Array.from(this.listboxTarget.querySelectorAll(".admin-original-song-option"))
  }

  resolvePastedRows(text) {
    const rows = this.pastedRows(text)
    const pickerElements = Array.from(document.querySelectorAll('[data-controller~="admin-original-song-picker"]'))
    const startIndex = pickerElements.indexOf(this.element)
    if (startIndex < 0) return

    rows.forEach((rowText, offset) => {
      if (!rowText) return

      const pickerElement = pickerElements[startIndex + offset]
      if (!pickerElement) return

      pickerElement.dispatchEvent(new CustomEvent("admin-original-song-picker:resolve-row", {
        detail: { text: rowText }
      }))
    })
  }

  pastedRows(text) {
    const rows = text
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .split("\n")
      .map((row) => this.pastedRowValue(row))

    while (rows.length > 0 && rows[0] === "") {
      rows.shift()
    }

    while (rows.length > 0 && rows[rows.length - 1] === "") {
      rows.pop()
    }

    return rows
  }

  pastedRowValue(row) {
    const cells = row.split("\t").map((cell) => cell.trim()).filter(Boolean)
    if (cells.length > 0) return this.normalizePastedCell(cells[cells.length - 1])

    return this.normalizePastedCell(row)
  }

  normalizePastedCell(value) {
    const trimmedValue = value.trim()
    if (/^["'`]{3,}$/.test(trimmedValue)) return ""

    return trimmedValue.replace(/^原曲\s*[:：]\s*/, "").trim()
  }

  missingQueryInputFor(element) {
    const container = element.closest(".admin-original-song-missing-query")
    return container?.querySelector(".admin-original-song-missing-input")
  }

  syncHiddenValue() {
    this.hiddenTarget.value = this.selectedOptions.map((option) => option.value).join(",")
  }
}
