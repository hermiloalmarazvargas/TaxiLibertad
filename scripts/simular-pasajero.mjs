// Pasajero simulado: se registra y pide un taxi, como lo hará la app del
// pasajero (fase 4). Sirve para probar la app del conductor en el teléfono.
// Solo para Supabase LOCAL.
//
// Uso:
//   npm run simular:pasajero                      → pide cerca del taxi disponible más cercano al centro
//   npm run simular:pasajero -- --lat 16.33 --lng -96.59 --referencia "Frente al mercado"
//   npm run simular:pasajero -- --destino-lat 16.34 --destino-lng -96.596
//
// Muestra en vivo lo que pasa con el viaje. Ctrl+C cancela el viaje y sale.
import { randomInt, randomUUID } from 'node:crypto';
import { parseArgs } from 'node:util';
import { createClient } from '@supabase/supabase-js';
import { crearClienteAdmin } from './lib/supabase-admin.mjs';

const url = process.env.SUPABASE_URL;
if (!/127\.0\.0\.1|localhost/.test(url ?? '')) {
  console.error('Este script solo corre contra Supabase local.');
  process.exit(1);
}

const { values: args } = parseArgs({
  options: {
    lat: { type: 'string' },
    lng: { type: 'string' },
    referencia: { type: 'string', default: 'Frente a la iglesia (prueba)' },
    'destino-lat': { type: 'string' },
    'destino-lng': { type: 'string' },
  },
});

const ESTADOS = {
  buscando: 'Buscando taxi…',
  asignado: '🚕 Taxi asignado: viene en camino',
  conductor_llego: '📍 El taxi llegó',
  en_curso: '🛣️  En viaje',
  completado: '✅ Viaje terminado',
  cancelado: '✖ Viaje cancelado',
  sin_conductor: '⚠ Nadie aceptó (sin conductor)',
};

async function origenPorOmision() {
  // ~150 m al norte del taxi disponible con ubicación, para que se lo ofrezcan.
  const { data } = await crearClienteAdmin()
    .from('conductor_estado')
    .select('lat, lng')
    .eq('estado', 'disponible')
    .not('ubicacion', 'is', null)
    .order('ubicacion_en', { ascending: false })
    .limit(1);
  if (data?.[0]) return { lat: data[0].lat + 0.00135, lng: data[0].lng };
  console.log('(No hay taxis disponibles con ubicación; se pide en el centro de Miahuatlán.)');
  return { lat: 16.329, lng: -96.596 };
}

async function main() {
  const pasajero = createClient(url, process.env.SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const telefono = `951${randomInt(1000000, 9999999)}`;
  const { error: e1 } = await pasajero.auth.signInAnonymously();
  if (e1) throw e1;
  const { error: e2 } = await pasajero.rpc('registrar_pasajero', { p_nombre: 'Pasajero Simulado', p_telefono: telefono });
  if (e2) throw e2;
  await pasajero.auth.refreshSession(); // para que el token traiga rol=pasajero

  const origen = args.lat && args.lng ? { lat: Number(args.lat), lng: Number(args.lng) } : await origenPorOmision();
  const { data: viaje, error: e3 } = await pasajero.rpc('solicitar_viaje', {
    p_client_request_id: randomUUID(),
    p_origen_lat: origen.lat,
    p_origen_lng: origen.lng,
    p_origen_referencia: args.referencia,
    p_destino_lat: args['destino-lat'] ? Number(args['destino-lat']) : undefined,
    p_destino_lng: args['destino-lng'] ? Number(args['destino-lng']) : undefined,
  });
  if (e3) throw e3;

  console.log(`Pasajero Simulado (${telefono}) pidió un taxi en ${origen.lat.toFixed(5)}, ${origen.lng.toFixed(5)}`);
  console.log(`Referencia: ${args.referencia}`);
  console.log(viaje.tarifa_monto ? `Tarifa: $${viaje.tarifa_monto}` : 'Tarifa: a convenir');
  console.log(`${ESTADOS[viaje.estado]}   (Ctrl+C para cancelar)\n`);

  let estado = viaje.estado;
  pasajero
    .channel('viaje-simulado')
    .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'viajes', filter: `id=eq.${viaje.id}` }, async ({ new: v }) => {
      if (v.estado === estado) return;
      estado = v.estado;
      let linea = ESTADOS[v.estado] ?? v.estado;
      if (v.estado === 'asignado') {
        const { data } = await pasajero.rpc('mi_viaje_activo');
        if (data?.[0]) linea += ` — ${data[0].conductor_nombre}, unidad ${data[0].unidad_numero} (${data[0].unidad_placas})`;
      }
      console.log(`${new Date().toLocaleTimeString('es-MX')}  ${linea}`);
      if (['completado', 'cancelado'].includes(v.estado)) process.exit(0);
    })
    .subscribe();

  process.on('SIGINT', async () => {
    if (!['completado', 'cancelado'].includes(estado)) {
      await pasajero.rpc('cancelar_viaje', { p_viaje_id: viaje.id, p_motivo: 'Prueba terminada' });
      console.log('\nViaje cancelado.');
    }
    process.exit(0);
  });
}

main().catch((error) => {
  console.error('✘', error.message ?? error);
  process.exitCode = 1;
});
