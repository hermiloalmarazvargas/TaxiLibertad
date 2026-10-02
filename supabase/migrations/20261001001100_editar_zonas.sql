-- =====================================================================
-- Fase 2: dibujar zonas y capturar tarifas desde el panel
-- · La API ya entrega zonas.poligono como GeoJSON (PostGIS 3).
-- · Para guardar, el panel manda GeoJSON a guardar_zona(), que lo valida.
-- · Las tarifas se editan directo en la tabla (RLS: solo admin); un
--   trigger registra quién y cuándo las cambió.
-- =====================================================================

-- p_id null = zona nueva.
create function public.guardar_zona(
  p_nombre   text,
  p_color    text,
  p_geojson  jsonb,
  p_id       bigint default null
) returns public.zonas
language plpgsql security definer set search_path = '' as $$
declare
  v_geom  extensions.geometry;
  v_zona  public.zonas;
begin
  perform privado.exigir_rol('admin');

  begin
    v_geom := extensions.st_multi(
      extensions.st_setsrid(extensions.st_geomfromgeojson(p_geojson::text), 4326));
  exception when others then
    perform privado.error('poligono_invalido', 'La forma de la zona no es válida');
  end;

  if extensions.geometrytype(v_geom) <> 'MULTIPOLYGON' then
    perform privado.error('poligono_invalido', 'La zona debe ser un polígono');
  end if;
  if not extensions.st_isvalid(v_geom) then
    perform privado.error('poligono_invalido',
      'La zona se cruza consigo misma. Vuelve a dibujarla sin que sus lados se crucen.');
  end if;
  if extensions.st_npoints(v_geom) > 500 then
    perform privado.error('poligono_invalido', 'La zona tiene demasiados puntos (máximo 500)');
  end if;
  -- Límite de cordura: ninguna zona de un municipio mide más de 500 km².
  if extensions.st_area(v_geom::extensions.geography) > 500e6 then
    perform privado.error('poligono_invalido', 'La zona es demasiado grande; revisa el dibujo');
  end if;

  begin
    if p_id is null then
      insert into public.zonas (nombre, color, poligono)
      values (trim(p_nombre), p_color, v_geom)
      returning * into v_zona;
    else
      update public.zonas
      set nombre = trim(p_nombre), color = p_color, poligono = v_geom
      where id = p_id
      returning * into v_zona;
      if not found then
        perform privado.error('zona_no_encontrada', 'La zona no existe');
      end if;
    end if;
  exception when unique_violation then
    perform privado.error('nombre_repetido', 'Ya existe una zona con ese nombre');
  end;

  return v_zona;
end;
$$;

revoke execute on function public.guardar_zona(text, text, jsonb, bigint) from public, anon;
grant execute on function public.guardar_zona(text, text, jsonb, bigint) to authenticated;

-- Quién y cuándo cambió una tarifa (el cliente no puede falsificarlo).
create function privado.tarifa_marcar_cambio() returns trigger
language plpgsql as $$
begin
  new.actualizado_por := auth.uid();
  new.actualizado_en := now();
  return new;
end;
$$;

create trigger tarifas_marcar_cambio
  before insert or update on public.tarifas
  for each row execute function privado.tarifa_marcar_cambio();

revoke all on all functions in schema privado from public, anon, authenticated;
