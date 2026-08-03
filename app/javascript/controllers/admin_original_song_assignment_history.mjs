const MAX_HISTORY_ENTRIES = 50
const HISTORY_PROPERTY = Symbol("adminOriginalSongAssignmentHistory")

export function isOriginalSongUndoShortcut(event) {
  return (event.ctrlKey || event.metaKey) && !event.shiftKey && event.key.toLowerCase() === "z"
}

export function isOriginalSongRedoShortcut(event) {
  return (event.ctrlKey || event.metaKey) && event.shiftKey && event.key.toLowerCase() === "z"
}

export function cloneOriginalSongOptions(options) {
  return (options || []).map((option) => ({ ...option }))
}

function sameOriginalSongOptions(left, right) {
  if (left.length !== right.length) return false

  return left.every((option, index) => (
    option.value === right[index]?.value && option.label === right[index]?.label
  ))
}

export class AdminOriginalSongAssignmentHistory {
  constructor() {
    this.controllers = new Map()
    this.undoStack = []
    this.redoStack = []
  }

  register(element, controller) {
    this.controllers.set(element, controller)
  }

  unregister(element) {
    this.controllers.delete(element)
  }

  controllerFor(element) {
    return this.controllers.get(element)
  }

  begin(changes, { pending = 0 } = {}) {
    const entry = {
      changes: changes.map(({ element, before }) => ({
        element,
        before: cloneOriginalSongOptions(before),
        after: cloneOriginalSongOptions(before)
      })),
      pending,
      state: "applied"
    }

    this.undoStack.push(entry)
    this.redoStack = []
    this.trimUndoStack()

    return entry
  }

  record(element, before, after) {
    const entry = this.begin([{ element, before }], { pending: 1 })
    this.update(entry, element, after)
    this.complete(entry)
    return entry
  }

  update(entry, element, after) {
    if (!entry || entry.state !== "applied") return

    const change = entry.changes.find((candidate) => candidate.element === element)
    if (!change) return

    change.after = cloneOriginalSongOptions(after)
  }

  complete(entry) {
    if (!entry) return

    entry.pending = Math.max(0, entry.pending - 1)
    if (entry.pending === 0 && !this.hasChanges(entry)) this.discard(entry)
  }

  undo() {
    const entry = this.undoStack.pop()
    if (!entry) return false

    entry.state = "undone"
    entry.changes.forEach((change) => {
      this.controllerFor(change.element)?.restoreSelectedOptions(change.before)
    })
    this.redoStack.push(entry)
    return true
  }

  redo() {
    const entry = this.redoStack.pop()
    if (!entry) return false

    entry.state = "applied"
    entry.changes.forEach((change) => {
      this.controllerFor(change.element)?.restoreSelectedOptions(change.after)
    })
    this.undoStack.push(entry)
    this.trimUndoStack()
    return true
  }

  discard(entry) {
    this.undoStack = this.undoStack.filter((candidate) => candidate !== entry)
    this.redoStack = this.redoStack.filter((candidate) => candidate !== entry)
  }

  hasChanges(entry) {
    return entry.changes.some((change) => !sameOriginalSongOptions(change.before, change.after))
  }

  trimUndoStack() {
    if (this.undoStack.length > MAX_HISTORY_ENTRIES) {
      this.undoStack.splice(0, this.undoStack.length - MAX_HISTORY_ENTRIES)
    }
  }
}

export function originalSongAssignmentHistoryFor(element) {
  const owner = element.closest('form') || element
  if (!owner[HISTORY_PROPERTY]) owner[HISTORY_PROPERTY] = new AdminOriginalSongAssignmentHistory()

  return owner[HISTORY_PROPERTY]
}
