-- =====================================================================
-- Datos de prueba para desarrollo local (se cargan con `supabase db reset`).
-- Las zonas son rectángulos APROXIMADOS alrededor del centro de Miahuatlán;
-- se dibujarán las reales desde el panel en la fase 2.
-- Hay huecos a propósito (al este y oeste del Centro) para probar "fuera de zona".
-- =====================================================================

insert into public.sitios (nombre, ubicacion, telefono) values
  ('Sitio Centro', public.punto(16.3290, -96.5960), '+529510000001');

insert into public.unidades (sitio_id, numero_economico, placas, marca, color)
select s.id, u.numero_economico, u.placas, u.marca, u.color
from public.sitios s
cross join (values
  ('01', 'TAX0001', 'Nissan Tsuru', 'Blanco/Rojo'),
  ('02', 'TAX0002', 'Nissan Tsuru', 'Blanco/Rojo'),
  ('03', 'TAX0003', 'Nissan V-Drive', 'Blanco/Rojo')
) as u (numero_economico, placas, marca, color)
where s.nombre = 'Sitio Centro';

insert into public.zonas (nombre, color, poligono) values
  ('Centro', '#dc2626', extensions.st_multi(extensions.st_geomfromtext(
    'POLYGON((-96.6000 16.3250, -96.5920 16.3250, -96.5920 16.3330, -96.6000 16.3330, -96.6000 16.3250))', 4326))),
  ('Norte', '#2563eb', extensions.st_multi(extensions.st_geomfromtext(
    'POLYGON((-96.6100 16.3330, -96.5820 16.3330, -96.5820 16.3500, -96.6100 16.3500, -96.6100 16.3330))', 4326))),
  ('Sur', '#16a34a', extensions.st_multi(extensions.st_geomfromtext(
    'POLYGON((-96.6100 16.3080, -96.5820 16.3080, -96.5820 16.3250, -96.6100 16.3250, -96.6100 16.3080))', 4326)));

-- Tarifas simétricas de ejemplo (se insertan ambas direcciones).
insert into public.tarifas (zona_origen_id, zona_destino_id, monto)
select zo.id, zd.id, t.monto
from (values
  ('Centro', 'Centro', 35),
  ('Norte',  'Norte',  40),
  ('Sur',    'Sur',    40),
  ('Centro', 'Norte',  45), ('Norte', 'Centro', 45),
  ('Centro', 'Sur',    45), ('Sur',   'Centro', 45),
  ('Norte',  'Sur',    60), ('Sur',   'Norte',  60)
) as t (origen, destino, monto)
join public.zonas zo on zo.nombre = t.origen
join public.zonas zd on zd.nombre = t.destino;
