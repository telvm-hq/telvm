import * as THREE from "three"

/** Orthographic pixel baseline for /minigames — gameplay comes later. */
export const dungeonHooks = {
  SpeedeelDungeon: {
    mounted() {
      const root = this.el
      this._disposed = false

      const canvas = document.createElement("canvas")
      canvas.style.cssText =
        "position:absolute;inset:0;width:100%;height:100%;display:block;touch-action:manipulation"
      root.appendChild(canvas)

      const internalW = 320
      const internalH = 180

      const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false })
      renderer.setClearColor(0x0d0a12, 1)
      renderer.setPixelRatio(1)
      renderer.setSize(internalW, internalH, false)

      const scene = new THREE.Scene()
      const half = 8
      const camera = new THREE.OrthographicCamera(-half, half, half, -half, 0.1, 100)
      camera.position.set(0, 0, 10)
      camera.lookAt(0, 0, 0)

      const stone = new THREE.Color(0x3a2f3d)
      const floor = new THREE.Mesh(
        new THREE.PlaneGeometry(14, 8),
        new THREE.MeshBasicMaterial({ color: stone })
      )
      floor.position.z = 0
      scene.add(floor)

      const ember = new THREE.Mesh(
        new THREE.PlaneGeometry(2.2, 0.35),
        new THREE.MeshBasicMaterial({ color: 0xd4a017 })
      )
      ember.position.set(0, 2.2, 0.05)
      scene.add(ember)

      const updateCam = () => {
        const w = Math.max(root.clientWidth, 1)
        const h = Math.max(root.clientHeight, 1)
        canvas.style.width = `${w}px`
        canvas.style.height = `${h}px`
        renderer.setSize(internalW, internalH, false)
      }

      this._resizeObs = new ResizeObserver(() => {
        if (!this._disposed) updateCam()
      })
      this._resizeObs.observe(root)

      root.addEventListener("click", () => root.focus())

      const t0 = performance.now()
      const tick = (t) => {
        if (this._disposed) return
        const pulse = 0.85 + 0.15 * Math.sin((t - t0) * 0.004)
        ember.material.color.setRGB(0.83 * pulse, 0.63 * pulse, 0.09 * pulse)
        renderer.render(scene, camera)
        this._rafId = requestAnimationFrame(tick)
      }

      this._cleanup = () => {
        this._disposed = true
        cancelAnimationFrame(this._rafId)
        this._resizeObs?.disconnect()
        floor.geometry.dispose()
        floor.material.dispose()
        ember.geometry.dispose()
        ember.material.dispose()
        canvas.remove()
        renderer.dispose()
      }

      updateCam()
      this._rafId = requestAnimationFrame(tick)
    },

    destroyed() {
      this._cleanup?.()
    }
  }
}
