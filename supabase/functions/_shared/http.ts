// Utilidades HTTP compartidas por las Edge Functions.

// El panel llama desde el navegador (otro origen): hace falta CORS.
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Mismo formato que los errores de las RPC: mensaje para el usuario y un
// código estable para que el cliente decida qué hacer.
export function error(status: number, codigo: string, mensaje: string): Response {
  return json(status, { error: mensaje, codigo });
}
