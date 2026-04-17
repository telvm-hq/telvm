import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks} from "./hooks/speedeel_race.js"

const csrf = document.querySelector("meta[name='csrf-token']")
const token = csrf && csrf.getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: token},
  hooks
})

liveSocket.connect()
window.liveSocket = liveSocket
