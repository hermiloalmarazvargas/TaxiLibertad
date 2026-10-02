import L from 'leaflet'

// Geoman (dibujo de polígonos) espera Leaflet como variable global `L`.
// Este módulo debe importarse ANTES que '@geoman-io/leaflet-geoman-free'.
declare global {
  interface Window {
    L: typeof L
  }
}
window.L = L

export default L
