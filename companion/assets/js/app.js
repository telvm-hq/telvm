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
import {hooks as colocatedHooks} from "phoenix-colocated/companion"
import topbar from "../vendor/topbar"

// MonacoExplorer — read-only file viewer loaded from CDN.
// The LiveView sets data-content on the element whenever a file is selected.
// mounted() bootstraps Monaco; updated() syncs content and language.
const MonacoExplorer = {
  mounted() {
    this._initMonaco()
  },
  updated() {
    const content = this.el.dataset.content || ""
    if (this._editor) {
      const model = this._editor.getModel()
      if (model && model.getValue() !== content) {
        model.setValue(content)
        const lang = this._detectLanguage(this.el.dataset.contentPath || "")
        monaco.editor.setModelLanguage(model, lang)
      }
    } else {
      // Monaco not yet ready — queue content and init
      this._pendingContent = content
      this._initMonaco()
    }
  },
  _initMonaco() {
    if (this._editor || this._loading) return
    this._loading = true

    const container = this.el
    const self = this

    // Workers must load from the CDN, not from the app origin — otherwise the
    // browser requests /vs/... on localhost and the lab HTTP port can see
    // stray GETs that are not the real probe response.
    const monacoBase = "https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min"
    // Must be on window — the loader reads global MonacoEnvironment, not the hook instance.
    window.MonacoEnvironment = {
      getWorkerUrl(_moduleId, label) {
        if (label === "json") return `${monacoBase}/vs/language/json/jsonWorker.js`
        if (label === "css" || label === "scss" || label === "less")
          return `${monacoBase}/vs/language/css/cssWorker.js`
        if (label === "html" || label === "handlebars" || label === "razor")
          return `${monacoBase}/vs/language/html/htmlWorker.js`
        if (label === "typescript" || label === "javascript")
          return `${monacoBase}/vs/language/typescript/tsWorker.js`
        return `${monacoBase}/vs/editor/editor.worker.js`
      }
    }

    // Load Monaco from CDN using its require-style loader.
    // The script is injected once; subsequent calls reuse the global require.
    if (!window.__monacoLoaded) {
      window.__monacoLoaded = true
      const script = document.createElement("script")
      script.src = "https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs/loader.js"
      script.onload = () => self._bootstrapMonaco(container)
      document.head.appendChild(script)
    } else if (window.monaco) {
      this._bootstrapMonaco(container)
    } else {
      // Loader script exists but monaco not yet ready — wait
      const interval = setInterval(() => {
        if (window.monaco) {
          clearInterval(interval)
          self._bootstrapMonaco(container)
        }
      }, 100)
    }
  },
  _bootstrapMonaco(container) {
    const self = this
    require.config({
      paths: { vs: "https://cdn.jsdelivr.net/npm/monaco-editor@0.52.0/min/vs" }
    })
    require(["vs/editor/editor.main"], () => {
      const content = self._pendingContent || container.dataset.content || ""
      const lang = self._detectLanguage(container.dataset.contentPath || "")

      self._editor = monaco.editor.create(container, {
        value: content,
        language: lang,
        readOnly: true,
        theme: "vs-dark",
        fontSize: 12,
        lineNumbers: "on",
        minimap: { enabled: false },
        scrollBeyondLastLine: false,
        wordWrap: "on",
        automaticLayout: true,
        renderLineHighlight: "none",
        contextmenu: false,
        scrollbar: { verticalScrollbarSize: 6, horizontalScrollbarSize: 6 }
      })
      self._loading = false
      delete self._pendingContent
    })
  },
  _detectLanguage(path) {
    if (!path) return "plaintext"
    const ext = path.split(".").pop().toLowerCase()
    const map = {
      js: "javascript", ts: "typescript", jsx: "javascript", tsx: "typescript",
      ex: "elixir", exs: "elixir", eex: "html",
      py: "python", rb: "ruby", go: "go", rs: "rust", zig: "zig",
      json: "json", yaml: "yaml", yml: "yaml", toml: "toml",
      sh: "shell", bash: "shell", zsh: "shell",
      md: "markdown", html: "html", css: "css", sql: "sql",
      dockerfile: "dockerfile", Dockerfile: "dockerfile",
      c: "c", cpp: "cpp", h: "c",
    }
    return map[ext] || "plaintext"
  },
  destroyed() {
    if (this._editor) {
      this._editor.dispose()
      this._editor = null
    }
  }
}

const Hooks = {
  ScrollBottom: {
    mounted() {
      this.scrollToBottom()
    },
    updated() {
      this.scrollToBottom()
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  MonacoExplorer
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks}
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


