import assert from "node:assert/strict"
import test from "node:test"

import {
  AdminOriginalSongAssignmentHistory,
  isOriginalSongRedoShortcut,
  isOriginalSongUndoShortcut
} from "../../app/javascript/controllers/admin_original_song_assignment_history.mjs"
import { shouldDistributePastedRows } from "../../app/javascript/controllers/admin_original_song_paste.mjs"

function buildController(options = []) {
  return {
    options: [...options],
    restoreSelectedOptions(nextOptions) {
      this.options = nextOptions.map((option) => ({ ...option }))
    }
  }
}

test("undoes and redoes a single-track original song change", () => {
  const history = new AdminOriginalSongAssignmentHistory()
  const element = {}
  const controller = buildController()
  history.register(element, controller)

  history.record(element, [], [{ value: "song-1", label: "Song 1" }])
  controller.options = [{ value: "song-1", label: "Song 1" }]

  assert.equal(history.undo(), true)
  assert.deepEqual(controller.options, [])
  assert.equal(history.redo(), true)
  assert.deepEqual(controller.options, [{ value: "song-1", label: "Song 1" }])
})

test("undoes and redoes a distributed paste as one history entry", () => {
  const history = new AdminOriginalSongAssignmentHistory()
  const firstElement = {}
  const secondElement = {}
  const firstController = buildController()
  const secondController = buildController()
  history.register(firstElement, firstController)
  history.register(secondElement, secondController)

  const entry = history.begin([
    { element: firstElement, before: [] },
    { element: secondElement, before: [] }
  ], { pending: 2 })
  firstController.options = [{ value: "song-1", label: "Song 1" }]
  secondController.options = [{ value: "song-2", label: "Song 2" }]
  history.update(entry, firstElement, firstController.options)
  history.update(entry, secondElement, secondController.options)
  history.complete(entry)
  history.complete(entry)

  assert.equal(history.undo(), true)
  assert.deepEqual(firstController.options, [])
  assert.deepEqual(secondController.options, [])
  assert.equal(history.redo(), true)
  assert.deepEqual(firstController.options, [{ value: "song-1", label: "Song 1" }])
  assert.deepEqual(secondController.options, [{ value: "song-2", label: "Song 2" }])
})

test("clears redo history after a new change", () => {
  const history = new AdminOriginalSongAssignmentHistory()
  const element = {}
  const controller = buildController()
  history.register(element, controller)

  history.record(element, [], [{ value: "song-1", label: "Song 1" }])
  controller.options = [{ value: "song-1", label: "Song 1" }]
  history.undo()
  history.record(element, [], [{ value: "song-2", label: "Song 2" }])

  assert.equal(history.redo(), false)
})

test("ignores a late async result after undoing a pending change", () => {
  const history = new AdminOriginalSongAssignmentHistory()
  const element = {}
  const controller = buildController()
  history.register(element, controller)

  const entry = history.begin([{ element, before: [] }], { pending: 1 })
  assert.equal(history.undo(), true)
  history.update(entry, element, [{ value: "late-song", label: "Late Song" }])
  history.complete(entry)

  assert.deepEqual(controller.options, [])
  assert.equal(history.redo(), false)
})

test("uses held Shift state for delimiter-free multi-line paste", () => {
  const rows = ["Bad Apple!!", "Dim. Dream"]

  assert.equal(shouldDistributePastedRows(rows, false), false)
  assert.equal(shouldDistributePastedRows(rows, true), true)
  assert.equal(shouldDistributePastedRows(["Song A / Song B"], false), true)
})

test("uses Ctrl/Cmd+Shift+Z for redo and does not treat Ctrl/Cmd+Y as redo", () => {
  assert.equal(isOriginalSongUndoShortcut({ ctrlKey: true, metaKey: false, shiftKey: false, key: "z" }), true)
  assert.equal(isOriginalSongUndoShortcut({ ctrlKey: false, metaKey: true, shiftKey: false, key: "Z" }), true)
  assert.equal(isOriginalSongUndoShortcut({ ctrlKey: true, metaKey: false, shiftKey: true, key: "z" }), false)

  assert.equal(isOriginalSongRedoShortcut({ ctrlKey: true, metaKey: false, shiftKey: true, key: "z" }), true)
  assert.equal(isOriginalSongRedoShortcut({ ctrlKey: false, metaKey: true, shiftKey: true, key: "Z" }), true)
  assert.equal(isOriginalSongRedoShortcut({ ctrlKey: true, metaKey: false, shiftKey: false, key: "y" }), false)
})
