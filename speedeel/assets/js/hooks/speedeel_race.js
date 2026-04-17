import * as THREE from "three"

const ORANGE = 0xff7a18
const TRACK = 0x111111
const LINE = 0xf5f5f5

function disposeMesh(mesh) {
  if (!mesh) return
  mesh.geometry?.dispose?.()
  if (mesh.material) {
    if (Array.isArray(mesh.material)) mesh.material.forEach((m) => m.dispose?.())
    else mesh.material.dispose?.()
  }
}

export const hooks = {
  SpeedeelRace: {
    mounted() {
      const root = this.el
      this._disposed = false
      this.keys = { ArrowUp: false, ArrowDown: false, ArrowLeft: false, ArrowRight: false }
      this.pointerKeys = { ArrowUp: false, ArrowDown: false, ArrowLeft: false, ArrowRight: false }

      const canvas = document.createElement("canvas")
      canvas.style.cssText = "position:absolute;inset:0;width:100%;height:100%;display:block"
      root.appendChild(canvas)

      const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false })
      renderer.setClearColor(0x000000, 1)
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))

      const scene = new THREE.Scene()

      const halfW = 14
      const halfH = 8

      const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100)
      camera.position.set(0, 0, 20)
      camera.lookAt(0, 0, 0)

      const track = new THREE.Mesh(
        new THREE.PlaneGeometry(halfW * 2, halfH * 2),
        new THREE.MeshBasicMaterial({ color: TRACK })
      )
      scene.add(track)

      const innerW = halfW - 0.35
      const innerH = halfH - 0.35
      const borderGeom = new THREE.BufferGeometry()
      const verts = new Float32Array([
        -innerW, -innerH, 0.02,
        innerW, -innerH, 0.02,
        innerW, innerH, 0.02,
        -innerW, innerH, 0.02,
        -innerW, -innerH, 0.02
      ])
      borderGeom.setAttribute("position", new THREE.BufferAttribute(verts, 3))
      const border = new THREE.Line(
        borderGeom,
        new THREE.LineBasicMaterial({ color: LINE })
      )
      scene.add(border)

      const outerGeom = new THREE.BufferGeometry()
      const verts2 = new Float32Array([
        -halfW, -halfH, 0.02,
        halfW, -halfH, 0.02,
        halfW, halfH, 0.02,
        -halfW, halfH, 0.02,
        -halfW, -halfH, 0.02
      ])
      outerGeom.setAttribute("position", new THREE.BufferAttribute(verts2, 3))
      const outerBorder = new THREE.Line(
        outerGeom,
        new THREE.LineBasicMaterial({ color: 0x555555 })
      )
      scene.add(outerBorder)

      const car = new THREE.Mesh(
        new THREE.BoxGeometry(0.55, 0.9, 0.25),
        new THREE.MeshBasicMaterial({ color: ORANGE })
      )
      car.position.set(0, -3, 0.2)
      scene.add(car)

      let vx = 0
      let vy = 0
      const accel = 22
      const damping = 0.94
      const maxSp = 9

      const clampBounds = () => {
        const margin = 0.5
        const maxX = innerW - margin
        const maxY = innerH - margin
        car.position.x = THREE.MathUtils.clamp(car.position.x, -maxX, maxX)
        car.position.y = THREE.MathUtils.clamp(car.position.y, -maxY, maxY)
      }

      const updateCam = () => {
        const aspect = Math.max(canvas.clientWidth, 1) / Math.max(canvas.clientHeight, 1)
        const viewH = halfH * 1.08
        const viewW = viewH * aspect
        camera.left = -viewW
        camera.right = viewW
        camera.top = viewH
        camera.bottom = -viewH
        camera.updateProjectionMatrix()
        renderer.setSize(canvas.clientWidth, canvas.clientHeight, false)
      }

      this._resizeObs = new ResizeObserver(() => {
        if (!this._disposed) updateCam()
      })
      this._resizeObs.observe(root)

      const keyActive = (code) => this.keys[code] || this.pointerKeys[code]

      const onKeyDown = (e) => {
        if (!this.keys.hasOwnProperty(e.code)) return
        if (document.activeElement !== root) return
        e.preventDefault()
        this.keys[e.code] = true
      }
      const onKeyUp = (e) => {
        if (!this.keys.hasOwnProperty(e.code)) return
        if (document.activeElement !== root) return
        this.keys[e.code] = false
      }

      window.addEventListener("keydown", onKeyDown, { passive: false })
      window.addEventListener("keyup", onKeyUp)
      this._onKeyDown = onKeyDown
      this._onKeyUp = onKeyUp

      root.addEventListener("click", () => root.focus())

      const pad = document.createElement("div")
      pad.style.cssText =
        "position:absolute;bottom:8px;right:8px;z-index:2;display:grid;grid-template-columns:repeat(3,36px);grid-template-rows:repeat(2,36px);gap:4px;padding:6px;border-radius:4px;border:1px solid rgba(255,255,255,0.15);background:rgba(10,10,10,0.85)"

      const btnStyle =
        "min-width:36px;min-height:36px;font:10px monospace;border-radius:3px;border:1px solid rgba(255,255,255,0.2);color:#ff7a18;background:rgba(0,0,0,0.55);cursor:pointer"

      const mkBtn = (label, codes) => {
        const b = document.createElement("button")
        b.type = "button"
        b.textContent = label
        b.style.cssText = btnStyle
        const down = (ev) => {
          ev.preventDefault()
          codes.forEach((c) => {
            this.pointerKeys[c] = true
          })
        }
        const up = (ev) => {
          ev.preventDefault()
          codes.forEach((c) => {
            this.pointerKeys[c] = false
          })
        }
        b.addEventListener("pointerdown", down)
        b.addEventListener("pointerup", up)
        b.addEventListener("pointerleave", up)
        b.addEventListener("pointercancel", up)
        return b
      }

      const u = mkBtn("↑", ["ArrowUp"])
      const l = mkBtn("←", ["ArrowLeft"])
      const d = mkBtn("↓", ["ArrowDown"])
      const r = mkBtn("→", ["ArrowRight"])
      const sp1 = document.createElement("div")
      const sp2 = document.createElement("div")
      pad.appendChild(sp1)
      pad.appendChild(u)
      pad.appendChild(sp2)
      pad.appendChild(l)
      pad.appendChild(d)
      pad.appendChild(r)
      root.appendChild(pad)

      let rafId = 0
      this._lastT = 0

      const tick = (t) => {
        if (this._disposed) return
        const dt = Math.min(0.05, (t - this._lastT) / 1000)
        this._lastT = t

        let ax = 0
        let ay = 0
        if (keyActive("ArrowLeft")) ax -= 1
        if (keyActive("ArrowRight")) ax += 1
        if (keyActive("ArrowUp")) ay += 1
        if (keyActive("ArrowDown")) ay -= 1

        if (ax !== 0 || ay !== 0) {
          const len = Math.hypot(ax, ay) || 1
          vx += (ax / len) * accel * dt
          vy += (ay / len) * accel * dt
        }

        vx *= damping
        vy *= damping
        const sp = Math.hypot(vx, vy)
        if (sp > maxSp) {
          vx = (vx / sp) * maxSp
          vy = (vy / sp) * maxSp
        }

        car.position.x += vx * dt
        car.position.y += vy * dt
        clampBounds()

        if (sp > 0.15) {
          car.rotation.z = Math.atan2(vx, vy)
        }

        renderer.render(scene, camera)
        rafId = requestAnimationFrame(tick)
      }

      this._cleanup = () => {
        this._disposed = true
        cancelAnimationFrame(rafId)
        this._resizeObs?.disconnect()
        window.removeEventListener("keydown", this._onKeyDown)
        window.removeEventListener("keyup", this._onKeyUp)
        pad.remove()
        canvas.remove()
        disposeMesh(track)
        disposeMesh(car)
        disposeMesh(border)
        disposeMesh(outerBorder)
        borderGeom.dispose()
        outerGeom.dispose()
        renderer.dispose()
      }

      updateCam()
      rafId = requestAnimationFrame(tick)
    },

    destroyed() {
      this._cleanup?.()
    }
  }
}
