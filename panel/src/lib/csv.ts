type Celda = string | number | null | undefined

function escapar(valor: Celda): string {
  const texto = valor == null ? '' : String(valor)
  return /[",\n\r]/.test(texto) ? `"${texto.replace(/"/g, '""')}"` : texto
}

// Descarga una tabla como CSV. El BOM inicial hace que Excel respete los
// acentos (UTF-8) al abrir el archivo con doble clic.
export function descargarCsv(nombreArchivo: string, encabezados: string[], filas: Celda[][]) {
  const contenido = [encabezados, ...filas].map((fila) => fila.map(escapar).join(',')).join('\r\n')
  const blob = new Blob(['﻿' + contenido], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const enlace = document.createElement('a')
  enlace.href = url
  enlace.download = nombreArchivo
  enlace.click()
  URL.revokeObjectURL(url)
}
