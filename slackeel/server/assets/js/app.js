// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/slackeel"
import topbar from "../vendor/topbar"

/**
 * Chat /chat message feed: follow new tokens when streaming, or if user is near
 * the bottom; otherwise do not yank the scroll when reading history.
 */
const ChatFeedScroll = {
  SCROLL_AT_BOTTOM_PX: 64,

  mounted() {
    this.scrollToBottom()
  },

  updated() {
    this.maybeScrollToBottom()
  },

  scrollToBottom() {
    const el = this.el
    if (!el || el.scrollHeight === 0) return
    el.scrollTop = el.scrollHeight
  },

  maybeScrollToBottom() {
    const el = this.el
    if (!el) return
    const pending = this.el.dataset?.chatPending === "true"
    if (pending) {
      this.scrollToBottom()
      return
    }
    const h = el.scrollHeight - el.clientHeight
    if (h <= 0) return
    if (h - el.scrollTop <= this.SCROLL_AT_BOTTOM_PX) {
      this.scrollToBottom()
    }
  },
}

/** Auto-scroll structured verify log (Preflight Ollama verify). */
const ScrollProbeLog = {
  mounted() {
    this.scrollToBottom()
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    const el = this.el.querySelector("[data-probe-log-scroll]")
    if (el) el.scrollTop = el.scrollHeight
  },
}

/** Keep the active model row in view on the mission board (smooth). */
const MissionBoard = {
  mounted() {
    this.scrollActiveRow()
  },
  updated() {
    this.scrollActiveRow()
  },
  scrollActiveRow() {
    const row = this.el.querySelector(".telvm-mission-row--current")
    if (row && typeof row.scrollIntoView === "function") {
      row.scrollIntoView({block: "nearest", behavior: "smooth"})
    }
  },
}

/** Pulse model rows + sync progress fills from `push_event("hot_model_phase", ...)`. */
const HotModelPhase = {
  mounted() {
    this._onPhase = (detail) => {
      const tag = detail?.tag
      const phase = detail?.phase
      if (!tag || !phase) return
      const esc = typeof CSS !== "undefined" && CSS.escape ? CSS.escape(tag) : String(tag).replace(/"/g, "")
      const rows = this.el.querySelectorAll(`[data-hot-tag="${esc}"]`)
      if (!rows || rows.length === 0) return

      rows.forEach((row) => {
        row.classList.remove("telvm-hot-row--js-pulse")
        void row.offsetWidth
        row.classList.add("telvm-hot-row--js-pulse")
        row.dataset.hotPhase = phase

        const fill = row.querySelector("[data-hot-progress-fill]")
        if (fill) {
          const p = detail.load_pct
          if (typeof p === "number" && Number.isFinite(p)) {
            fill.classList.remove("telvm-progress-fill--indeterminate")
            fill.style.width = `${Math.min(100, Math.max(0, p))}%`
          } else if (phase === "loading" || phase === "streaming") {
            fill.classList.add("telvm-progress-fill--indeterminate")
            fill.style.width = "32%"
          }
        }

        const unloadFill = row.querySelector("[data-hot-unload-fill]")
        if (unloadFill) {
          if (detail.unload_busy) {
            unloadFill.classList.add("telvm-progress-fill--unload-indeterminate")
          } else {
            unloadFill.classList.remove("telvm-progress-fill--unload-indeterminate")
          }
        }
      })

      const chatFill = this.el.querySelector("[data-chat-load-fill]")
      if (chatFill && detail.tag && String(detail.tag) === String(this.el.dataset?.chatPendingModel || "")) {
        const p2 = detail.load_pct
        if (typeof p2 === "number" && Number.isFinite(p2)) {
          chatFill.classList.remove("telvm-progress-fill--indeterminate")
          chatFill.style.width = `${Math.min(100, Math.max(0, p2))}%`
        }
      }
    }
    this.handleEvent("hot_model_phase", this._onPhase)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {
    ...colocatedHooks,
    ScrollProbeLog,
    MissionBoard,
    HotModelPhase,
    ChatFeedScroll,
  },
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

