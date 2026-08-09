import assert from "node:assert/strict"
import test from "node:test"

import AdminOriginalSongAlbumController from "../../app/javascript/controllers/admin_original_song_album_controller.js"

function buildController() {
  const controller = Object.create(AdminOriginalSongAlbumController.prototype)
  controller.hasUrlValue = true
  controller.urlValue = "/admin/track_original_song_assignments/albums/9777777779001"
  controller.loadingTextValue = "楽曲を読み込んでいます..."
  controller.errorTextValue = "楽曲の読み込みに失敗しました。"
  controller.retryTextValue = "再試行"
  controller.loaded = false
  controller.loading = false
  controller.contentTarget = {
    hidden: false,
    innerHTML: "",
    attributes: {},
    setAttribute(name, value) {
      this.attributes[name] = value
    },
    removeAttribute(name) {
      delete this.attributes[name]
    }
  }
  controller.statusTarget = {
    hidden: true,
    textContent: ""
  }
  controller.retryTarget = {
    hidden: true,
    textContent: ""
  }
  return controller
}

test("shows retry controls when an album response lacks the expected content", async () => {
  const previousFetch = globalThis.fetch
  const previousDOMParser = globalThis.DOMParser
  globalThis.fetch = async () => ({
    ok: true,
    text: async () => "<html><body>ログイン画面</body></html>"
  })
  globalThis.DOMParser = class {
    parseFromString() {
      return {
        querySelector() {
          return null
        }
      }
    }
  }

  try {
    const controller = buildController()
    await controller.loadTracks()

    assert.equal(controller.loaded, false)
    assert.equal(controller.loading, false)
    assert.equal(controller.contentTarget.innerHTML, "")
    assert.equal(controller.statusTarget.textContent, "楽曲の読み込みに失敗しました。")
    assert.equal(controller.retryTarget.textContent, "再試行")
    assert.equal(controller.retryTarget.hidden, false)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.DOMParser = previousDOMParser
  }
})

test("renders a valid empty album response as loaded content", async () => {
  const previousFetch = globalThis.fetch
  const previousDOMParser = globalThis.DOMParser
  globalThis.fetch = async () => ({
    ok: true,
    text: async () => '<div class="admin-original-song-album-empty">未設定楽曲はありません。</div>'
  })
  globalThis.DOMParser = class {
    parseFromString() {
      return {
        querySelector(selector) {
          return selector.includes("admin-original-song-album-empty") ? {} : null
        }
      }
    }
  }

  try {
    const controller = buildController()
    await controller.loadTracks()

    assert.equal(controller.loaded, true)
    assert.equal(controller.statusTarget.hidden, true)
    assert.equal(controller.contentTarget.hidden, false)
    assert.match(controller.contentTarget.innerHTML, /admin-original-song-album-empty/)
    assert.equal(controller.retryTarget.hidden, true)
  } finally {
    globalThis.fetch = previousFetch
    globalThis.DOMParser = previousDOMParser
  }
})
