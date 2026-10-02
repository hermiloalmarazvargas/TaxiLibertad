
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  
  "graphql_public": {
          Tables: {
            [_ in never]: never
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "graphql":
{ Args: { "extensions"?: Json,"operationName"?: string,"query"?: string,"variables"?: Json }; Returns: Json
                           }
          }
          Enums: {
            [_ in never]: never
          }
          CompositeTypes: {
            [_ in never]: never
          }
        },"public": {
          Tables: {
            "conductor_estado": {
                  Row: {
                    "actualizado_en": string,"conductor_id": string,"estado": Database["public"]['Enums']["estado_conductor"],"fuera_desde": string | null,"lat": number | null,"lng": number | null,"motivo_fuera": string | null,"ofertas_vencidas_seguidas": number,"precision_m": number | null,"rumbo": number | null,"ubicacion": unknown,"ubicacion_en": string | null,"unidad_id": number | null
                  }
                  Insert: {
                    "actualizado_en"?: string,"conductor_id": string,"estado"?: Database["public"]['Enums']["estado_conductor"],"fuera_desde"?: string | null,"lat"?: never,"lng"?: never,"motivo_fuera"?: string | null,"ofertas_vencidas_seguidas"?: number,"precision_m"?: number | null,"rumbo"?: number | null,"ubicacion"?: unknown,"ubicacion_en"?: string | null,"unidad_id"?: number | null
                  }
                  Update: {
                    "actualizado_en"?: string,"conductor_id"?: string,"estado"?: Database["public"]['Enums']["estado_conductor"],"fuera_desde"?: string | null,"lat"?: never,"lng"?: never,"motivo_fuera"?: string | null,"ofertas_vencidas_seguidas"?: number,"precision_m"?: number | null,"rumbo"?: number | null,"ubicacion"?: unknown,"ubicacion_en"?: string | null,"unidad_id"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "conductor_estado_conductor_id_fkey"
      columns: ["conductor_id"]
isOneToOne: true
      referencedRelation: "conductores"
      referencedColumns: ["perfil_id"]
    },{
      foreignKeyName: "conductor_estado_unidad_id_fkey"
      columns: ["unidad_id"]
isOneToOne: false
      referencedRelation: "unidades"
      referencedColumns: ["id"]
    }
                  ]
                },"conductores": {
                  Row: {
                    "activo": boolean,"creado_en": string,"perfil_id": string,"sitio_id": number
                  }
                  Insert: {
                    "activo"?: boolean,"creado_en"?: string,"perfil_id": string,"sitio_id": number
                  }
                  Update: {
                    "activo"?: boolean,"creado_en"?: string,"perfil_id"?: string,"sitio_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "conductores_perfil_id_fkey"
      columns: ["perfil_id"]
isOneToOne: true
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "conductores_sitio_id_fkey"
      columns: ["sitio_id"]
isOneToOne: false
      referencedRelation: "sitios"
      referencedColumns: ["id"]
    }
                  ]
                },"configuracion": {
                  Row: {
                    "actualizado_en": string,"actualizado_por": string | null,"id": boolean,"recargo_desde": string,"recargo_hasta": string,"recargo_nocturno_pct": number
                  }
                  Insert: {
                    "actualizado_en"?: string,"actualizado_por"?: string | null,"id"?: boolean,"recargo_desde"?: string,"recargo_hasta"?: string,"recargo_nocturno_pct"?: number
                  }
                  Update: {
                    "actualizado_en"?: string,"actualizado_por"?: string | null,"id"?: boolean,"recargo_desde"?: string,"recargo_hasta"?: string,"recargo_nocturno_pct"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "configuracion_actualizado_por_fkey"
      columns: ["actualizado_por"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    }
                  ]
                },"dispositivos": {
                  Row: {
                    "actualizado_en": string,"fcm_token": string,"id": number,"perfil_id": string,"plataforma": string
                  }
                  Insert: {
                    "actualizado_en"?: string,"fcm_token": string,"id"?: never,"perfil_id": string,"plataforma": string
                  }
                  Update: {
                    "actualizado_en"?: string,"fcm_token"?: string,"id"?: never,"perfil_id"?: string,"plataforma"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "dispositivos_perfil_id_fkey"
      columns: ["perfil_id"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    }
                  ]
                },"notificaciones": {
                  Row: {
                    "creada_en": string,"cuerpo": string,"datos": NonNullable<Json>,"enviada_en": string | null,"id": number,"leida_en": string | null,"perfil_id": string,"tipo": string,"titulo": string
                  }
                  Insert: {
                    "creada_en"?: string,"cuerpo": string,"datos"?: NonNullable<Json>,"enviada_en"?: string | null,"id"?: never,"leida_en"?: string | null,"perfil_id": string,"tipo": string,"titulo": string
                  }
                  Update: {
                    "creada_en"?: string,"cuerpo"?: string,"datos"?: NonNullable<Json>,"enviada_en"?: string | null,"id"?: never,"leida_en"?: string | null,"perfil_id"?: string,"tipo"?: string,"titulo"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "notificaciones_perfil_id_fkey"
      columns: ["perfil_id"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    }
                  ]
                },"ofertas_viaje": {
                  Row: {
                    "conductor_id": string,"distancia_m": number | null,"expira_en": string,"id": number,"ofrecido_en": string,"respondido_en": string | null,"respuesta": Database["public"]['Enums']["respuesta_oferta"],"viaje_id": string
                  }
                  Insert: {
                    "conductor_id": string,"distancia_m"?: number | null,"expira_en"?: string,"id"?: never,"ofrecido_en"?: string,"respondido_en"?: string | null,"respuesta"?: Database["public"]['Enums']["respuesta_oferta"],"viaje_id": string
                  }
                  Update: {
                    "conductor_id"?: string,"distancia_m"?: number | null,"expira_en"?: string,"id"?: never,"ofrecido_en"?: string,"respondido_en"?: string | null,"respuesta"?: Database["public"]['Enums']["respuesta_oferta"],"viaje_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "ofertas_viaje_conductor_id_fkey"
      columns: ["conductor_id"]
isOneToOne: false
      referencedRelation: "conductores"
      referencedColumns: ["perfil_id"]
    },{
      foreignKeyName: "ofertas_viaje_viaje_id_fkey"
      columns: ["viaje_id"]
isOneToOne: false
      referencedRelation: "viajes"
      referencedColumns: ["id"]
    }
                  ]
                },"perfiles": {
                  Row: {
                    "activo": boolean,"creado_en": string,"id": string,"nombre": string,"rol": Database["public"]['Enums']["rol_usuario"],"sitio_id": number | null,"telefono": string | null,"telefono_verificado": boolean,"usuario": string | null
                  }
                  Insert: {
                    "activo"?: boolean,"creado_en"?: string,"id": string,"nombre": string,"rol"?: Database["public"]['Enums']["rol_usuario"],"sitio_id"?: number | null,"telefono"?: string | null,"telefono_verificado"?: boolean,"usuario"?: string | null
                  }
                  Update: {
                    "activo"?: boolean,"creado_en"?: string,"id"?: string,"nombre"?: string,"rol"?: Database["public"]['Enums']["rol_usuario"],"sitio_id"?: number | null,"telefono"?: string | null,"telefono_verificado"?: boolean,"usuario"?: string | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "perfiles_sitio_id_fkey"
      columns: ["sitio_id"]
isOneToOne: false
      referencedRelation: "sitios"
      referencedColumns: ["id"]
    }
                  ]
                },"sitios": {
                  Row: {
                    "activo": boolean,"creado_en": string,"id": number,"nombre": string,"telefono": string | null,"ubicacion": unknown
                  }
                  Insert: {
                    "activo"?: boolean,"creado_en"?: string,"id"?: never,"nombre": string,"telefono"?: string | null,"ubicacion"?: unknown
                  }
                  Update: {
                    "activo"?: boolean,"creado_en"?: string,"id"?: never,"nombre"?: string,"telefono"?: string | null,"ubicacion"?: unknown
                  }
                  Relationships: [
                    
                  ]
                },"tarifas": {
                  Row: {
                    "actualizado_en": string,"actualizado_por": string | null,"monto": number,"zona_destino_id": number,"zona_origen_id": number
                  }
                  Insert: {
                    "actualizado_en"?: string,"actualizado_por"?: string | null,"monto": number,"zona_destino_id": number,"zona_origen_id": number
                  }
                  Update: {
                    "actualizado_en"?: string,"actualizado_por"?: string | null,"monto"?: number,"zona_destino_id"?: number,"zona_origen_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "tarifas_zona_destino_id_fkey"
      columns: ["zona_destino_id"]
isOneToOne: false
      referencedRelation: "zonas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "tarifas_zona_origen_id_fkey"
      columns: ["zona_origen_id"]
isOneToOne: false
      referencedRelation: "zonas"
      referencedColumns: ["id"]
    }
                  ]
                },"telefonos_bloqueados": {
                  Row: {
                    "bloqueado_en": string,"bloqueado_por": string | null,"motivo": string,"telefono": string
                  }
                  Insert: {
                    "bloqueado_en"?: string,"bloqueado_por"?: string | null,"motivo": string,"telefono": string
                  }
                  Update: {
                    "bloqueado_en"?: string,"bloqueado_por"?: string | null,"motivo"?: string,"telefono"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "telefonos_bloqueados_bloqueado_por_fkey"
      columns: ["bloqueado_por"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    }
                  ]
                },"unidades": {
                  Row: {
                    "activo": boolean,"color": string | null,"creado_en": string,"id": number,"marca": string | null,"modelo": string | null,"numero_economico": string,"placas": string,"sitio_id": number
                  }
                  Insert: {
                    "activo"?: boolean,"color"?: string | null,"creado_en"?: string,"id"?: never,"marca"?: string | null,"modelo"?: string | null,"numero_economico": string,"placas": string,"sitio_id": number
                  }
                  Update: {
                    "activo"?: boolean,"color"?: string | null,"creado_en"?: string,"id"?: never,"marca"?: string | null,"modelo"?: string | null,"numero_economico"?: string,"placas"?: string,"sitio_id"?: number
                  }
                  Relationships: [
                    {
      foreignKeyName: "unidades_sitio_id_fkey"
      columns: ["sitio_id"]
isOneToOne: false
      referencedRelation: "sitios"
      referencedColumns: ["id"]
    }
                  ]
                },"viaje_eventos": {
                  Row: {
                    "actor_id": string | null,"estado_anterior": Database["public"]['Enums']["estado_viaje"] | null,"estado_nuevo": Database["public"]['Enums']["estado_viaje"],"id": number,"ocurrido_en": string,"registrado_en": string,"viaje_id": string
                  }
                  Insert: {
                    "actor_id"?: string | null,"estado_anterior"?: Database["public"]['Enums']["estado_viaje"] | null,"estado_nuevo": Database["public"]['Enums']["estado_viaje"],"id"?: never,"ocurrido_en"?: string,"registrado_en"?: string,"viaje_id": string
                  }
                  Update: {
                    "actor_id"?: string | null,"estado_anterior"?: Database["public"]['Enums']["estado_viaje"] | null,"estado_nuevo"?: Database["public"]['Enums']["estado_viaje"],"id"?: never,"ocurrido_en"?: string,"registrado_en"?: string,"viaje_id"?: string
                  }
                  Relationships: [
                    {
      foreignKeyName: "viaje_eventos_actor_id_fkey"
      columns: ["actor_id"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viaje_eventos_viaje_id_fkey"
      columns: ["viaje_id"]
isOneToOne: false
      referencedRelation: "viajes"
      referencedColumns: ["id"]
    }
                  ]
                },"viajes": {
                  Row: {
                    "asignado_en": string | null,"canal": Database["public"]['Enums']["canal_viaje"],"cancelado_en": string | null,"cancelado_por": string | null,"client_request_id": string | null,"conductor_id": string | null,"contacto_nombre": string | null,"contacto_telefono": string | null,"creado_por": string | null,"destino": unknown,"destino_lat": number | null,"destino_lng": number | null,"destino_referencia": string | null,"estado": Database["public"]['Enums']["estado_viaje"],"id": string,"iniciado_en": string | null,"llego_en": string | null,"motivo_cancelacion": string | null,"origen": unknown,"origen_lat": number | null,"origen_lng": number | null,"origen_referencia": string | null,"pasajero_id": string | null,"sitio_id": number | null,"solicitado_en": string,"tarifa_monto": number | null,"tarifa_recargo": number | null,"terminado_en": string | null,"unidad_id": number | null,"zona_destino_id": number | null,"zona_origen_id": number | null
                  }
                  Insert: {
                    "asignado_en"?: string | null,"canal": Database["public"]['Enums']["canal_viaje"],"cancelado_en"?: string | null,"cancelado_por"?: string | null,"client_request_id"?: string | null,"conductor_id"?: string | null,"contacto_nombre"?: string | null,"contacto_telefono"?: string | null,"creado_por"?: string | null,"destino"?: unknown,"destino_lat"?: never,"destino_lng"?: never,"destino_referencia"?: string | null,"estado"?: Database["public"]['Enums']["estado_viaje"],"id"?: string,"iniciado_en"?: string | null,"llego_en"?: string | null,"motivo_cancelacion"?: string | null,"origen": unknown,"origen_lat"?: never,"origen_lng"?: never,"origen_referencia"?: string | null,"pasajero_id"?: string | null,"sitio_id"?: number | null,"solicitado_en"?: string,"tarifa_monto"?: number | null,"tarifa_recargo"?: number | null,"terminado_en"?: string | null,"unidad_id"?: number | null,"zona_destino_id"?: number | null,"zona_origen_id"?: number | null
                  }
                  Update: {
                    "asignado_en"?: string | null,"canal"?: Database["public"]['Enums']["canal_viaje"],"cancelado_en"?: string | null,"cancelado_por"?: string | null,"client_request_id"?: string | null,"conductor_id"?: string | null,"contacto_nombre"?: string | null,"contacto_telefono"?: string | null,"creado_por"?: string | null,"destino"?: unknown,"destino_lat"?: never,"destino_lng"?: never,"destino_referencia"?: string | null,"estado"?: Database["public"]['Enums']["estado_viaje"],"id"?: string,"iniciado_en"?: string | null,"llego_en"?: string | null,"motivo_cancelacion"?: string | null,"origen"?: unknown,"origen_lat"?: never,"origen_lng"?: never,"origen_referencia"?: string | null,"pasajero_id"?: string | null,"sitio_id"?: number | null,"solicitado_en"?: string,"tarifa_monto"?: number | null,"tarifa_recargo"?: number | null,"terminado_en"?: string | null,"unidad_id"?: number | null,"zona_destino_id"?: number | null,"zona_origen_id"?: number | null
                  }
                  Relationships: [
                    {
      foreignKeyName: "viajes_cancelado_por_fkey"
      columns: ["cancelado_por"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viajes_conductor_id_fkey"
      columns: ["conductor_id"]
isOneToOne: false
      referencedRelation: "conductores"
      referencedColumns: ["perfil_id"]
    },{
      foreignKeyName: "viajes_creado_por_fkey"
      columns: ["creado_por"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viajes_pasajero_id_fkey"
      columns: ["pasajero_id"]
isOneToOne: false
      referencedRelation: "perfiles"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viajes_sitio_id_fkey"
      columns: ["sitio_id"]
isOneToOne: false
      referencedRelation: "sitios"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viajes_unidad_id_fkey"
      columns: ["unidad_id"]
isOneToOne: false
      referencedRelation: "unidades"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viajes_zona_destino_id_fkey"
      columns: ["zona_destino_id"]
isOneToOne: false
      referencedRelation: "zonas"
      referencedColumns: ["id"]
    },{
      foreignKeyName: "viajes_zona_origen_id_fkey"
      columns: ["zona_origen_id"]
isOneToOne: false
      referencedRelation: "zonas"
      referencedColumns: ["id"]
    }
                  ]
                },"zonas": {
                  Row: {
                    "activa": boolean,"color": string,"creado_en": string,"id": number,"nombre": string,"poligono": unknown
                  }
                  Insert: {
                    "activa"?: boolean,"color"?: string,"creado_en"?: string,"id"?: never,"nombre": string,"poligono": unknown
                  }
                  Update: {
                    "activa"?: boolean,"color"?: string,"creado_en"?: string,"id"?: never,"nombre"?: string,"poligono"?: unknown
                  }
                  Relationships: [
                    
                  ]
                }
          }
          Views: {
            [_ in never]: never
          }
          Functions: {
            "asignar_viaje":
{ Args: { "p_conductor_id": string,"p_viaje_id": string }; Returns: {
              "asignado_en": string | null,
"canal": Database["public"]['Enums']["canal_viaje"],
"cancelado_en": string | null,
"cancelado_por": string | null,
"client_request_id": string | null,
"conductor_id": string | null,
"contacto_nombre": string | null,
"contacto_telefono": string | null,
"creado_por": string | null,
"destino": unknown,
"destino_lat": number | null,
"destino_lng": number | null,
"destino_referencia": string | null,
"estado": Database["public"]['Enums']["estado_viaje"],
"id": string,
"iniciado_en": string | null,
"llego_en": string | null,
"motivo_cancelacion": string | null,
"origen": unknown,
"origen_lat": number | null,
"origen_lng": number | null,
"origen_referencia": string | null,
"pasajero_id": string | null,
"sitio_id": number | null,
"solicitado_en": string,
"tarifa_monto": number | null,
"tarifa_recargo": number | null,
"terminado_en": string | null,
"unidad_id": number | null,
"zona_destino_id": number | null,
"zona_origen_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "viajes"
        isOneToOne: true
        isSetofReturn: false
      } },
"avanzar_viaje":
{ Args: { "p_estado": Database["public"]['Enums']["estado_viaje"],"p_ocurrido_en"?: string,"p_viaje_id": string }; Returns: {
              "asignado_en": string | null,
"canal": Database["public"]['Enums']["canal_viaje"],
"cancelado_en": string | null,
"cancelado_por": string | null,
"client_request_id": string | null,
"conductor_id": string | null,
"contacto_nombre": string | null,
"contacto_telefono": string | null,
"creado_por": string | null,
"destino": unknown,
"destino_lat": number | null,
"destino_lng": number | null,
"destino_referencia": string | null,
"estado": Database["public"]['Enums']["estado_viaje"],
"id": string,
"iniciado_en": string | null,
"llego_en": string | null,
"motivo_cancelacion": string | null,
"origen": unknown,
"origen_lat": number | null,
"origen_lng": number | null,
"origen_referencia": string | null,
"pasajero_id": string | null,
"sitio_id": number | null,
"solicitado_en": string,
"tarifa_monto": number | null,
"tarifa_recargo": number | null,
"terminado_en": string | null,
"unidad_id": number | null,
"zona_destino_id": number | null,
"zona_origen_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "viajes"
        isOneToOne: true
        isSetofReturn: false
      } },
"before_user_created_hook":
{ Args: { "event": Json }; Returns: Json
                           },
"cambiar_activo_conductor":
{ Args: { "p_activo": boolean,"p_conductor_id": string }; Returns: undefined
                           },
"cambiar_disponibilidad":
{ Args: { "p_estado": Database["public"]['Enums']["estado_conductor"],"p_unidad_id"?: number }; Returns: {
              "actualizado_en": string,
"conductor_id": string,
"estado": Database["public"]['Enums']["estado_conductor"],
"fuera_desde": string | null,
"lat": number | null,
"lng": number | null,
"motivo_fuera": string | null,
"ofertas_vencidas_seguidas": number,
"precision_m": number | null,
"rumbo": number | null,
"ubicacion": unknown,
"ubicacion_en": string | null,
"unidad_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "conductor_estado"
        isOneToOne: true
        isSetofReturn: false
      } },
"cancelar_viaje":
{ Args: { "p_motivo"?: string,"p_viaje_id": string }; Returns: {
              "asignado_en": string | null,
"canal": Database["public"]['Enums']["canal_viaje"],
"cancelado_en": string | null,
"cancelado_por": string | null,
"client_request_id": string | null,
"conductor_id": string | null,
"contacto_nombre": string | null,
"contacto_telefono": string | null,
"creado_por": string | null,
"destino": unknown,
"destino_lat": number | null,
"destino_lng": number | null,
"destino_referencia": string | null,
"estado": Database["public"]['Enums']["estado_viaje"],
"id": string,
"iniciado_en": string | null,
"llego_en": string | null,
"motivo_cancelacion": string | null,
"origen": unknown,
"origen_lat": number | null,
"origen_lng": number | null,
"origen_referencia": string | null,
"pasajero_id": string | null,
"sitio_id": number | null,
"solicitado_en": string,
"tarifa_monto": number | null,
"tarifa_recargo": number | null,
"terminado_en": string | null,
"unidad_id": number | null,
"zona_destino_id": number | null,
"zona_origen_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "viajes"
        isOneToOne: true
        isSetofReturn: false
      } },
"crear_perfil_conductor":
{ Args: { "p_nombre": string,"p_sitio_id": number,"p_telefono": string,"p_user_id": string,"p_usuario": string }; Returns: undefined
                           },
"crear_viaje_telefonico":
{ Args: { "p_client_request_id": string,"p_conductor_id"?: string,"p_contacto_nombre": string,"p_contacto_telefono": string,"p_destino_lat"?: number,"p_destino_lng"?: number,"p_destino_referencia"?: string,"p_origen_lat": number,"p_origen_lng": number,"p_origen_referencia"?: string }; Returns: {
              "asignado_en": string | null,
"canal": Database["public"]['Enums']["canal_viaje"],
"cancelado_en": string | null,
"cancelado_por": string | null,
"client_request_id": string | null,
"conductor_id": string | null,
"contacto_nombre": string | null,
"contacto_telefono": string | null,
"creado_por": string | null,
"destino": unknown,
"destino_lat": number | null,
"destino_lng": number | null,
"destino_referencia": string | null,
"estado": Database["public"]['Enums']["estado_viaje"],
"id": string,
"iniciado_en": string | null,
"llego_en": string | null,
"motivo_cancelacion": string | null,
"origen": unknown,
"origen_lat": number | null,
"origen_lng": number | null,
"origen_referencia": string | null,
"pasajero_id": string | null,
"sitio_id": number | null,
"solicitado_en": string,
"tarifa_monto": number | null,
"tarifa_recargo": number | null,
"terminado_en": string | null,
"unidad_id": number | null,
"zona_destino_id": number | null,
"zona_origen_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "viajes"
        isOneToOne: true
        isSetofReturn: false
      } },
"custom_access_token_hook":
{ Args: { "event": Json }; Returns: Json
                           },
"es_admin":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"es_staff":
{ Args: Record<PropertyKey, never>; Returns: boolean
                           },
"guardar_zona":
{ Args: { "p_color": string,"p_geojson": Json,"p_id"?: number,"p_nombre": string }; Returns: {
              "activa": boolean,
"color": string,
"creado_en": string,
"id": number,
"nombre": string,
"poligono": unknown
            }
                          SetofOptions: {
        from: "*"
        to: "zonas"
        isOneToOne: true
        isSetofReturn: false
      } },
"mi_oferta_pendiente":
{ Args: Record<PropertyKey, never>; Returns: {
              "destino_lat": number,"destino_lng": number,"destino_referencia": string,"distancia_m": number,"oferta_id": number,"origen_lat": number,"origen_lng": number,"origen_referencia": string,"segundos_restantes": number,"tarifa_monto": number,"viaje_id": string,"zona_destino": string,"zona_origen": string
            }[]
                           },
"mi_viaje_activo":
{ Args: Record<PropertyKey, never>; Returns: {
              "conductor_lat": number,"conductor_lng": number,"conductor_nombre": string,"conductor_ubicacion_en": string,"destino_lat": number,"destino_lng": number,"destino_referencia": string,"estado": Database["public"]['Enums']["estado_viaje"],"origen_lat": number,"origen_lng": number,"origen_referencia": string,"solicitado_en": string,"tarifa_monto": number,"unidad_descripcion": string,"unidad_numero": string,"unidad_placas": string,"viaje_id": string,"zona_destino": string,"zona_origen": string
            }[]
                           },
"mi_viaje_activo_conductor":
{ Args: Record<PropertyKey, never>; Returns: {
              "asignado_en": string,"canal": Database["public"]['Enums']["canal_viaje"],"destino_lat": number,"destino_lng": number,"destino_referencia": string,"estado": Database["public"]['Enums']["estado_viaje"],"origen_lat": number,"origen_lng": number,"origen_referencia": string,"pasajero_nombre": string,"pasajero_telefono": string,"tarifa_monto": number,"viaje_id": string,"zona_destino": string,"zona_origen": string
            }[]
                           },
"normalizar_telefono":
{ Args: { "p_telefono": string }; Returns: unknown
                           },
"puede_ver_sitio":
{ Args: { "p_sitio_id": number }; Returns: boolean
                           },
"punto":
{ Args: { "lat": number,"lng": number }; Returns: unknown
                           },
"registrar_pasajero":
{ Args: { "p_nombre": string,"p_telefono": string }; Returns: {
              "activo": boolean,
"creado_en": string,
"id": string,
"nombre": string,
"rol": Database["public"]['Enums']["rol_usuario"],
"sitio_id": number | null,
"telefono": string | null,
"telefono_verificado": boolean,
"usuario": string | null
            }
                          SetofOptions: {
        from: "*"
        to: "perfiles"
        isOneToOne: true
        isSetofReturn: false
      } },
"reporte_por_conductor":
{ Args: { "p_desde": string,"p_hasta": string }; Returns: {
              "a_convenir": number,"aceptadas": number,"activo": boolean,"completados": number,"conductor_id": string,"ingresos": number,"nombre": string,"ofertas": number,"rechazadas": number,"sitio": string,"soltados": number,"vencidas": number
            }[]
                           },
"reporte_por_dia":
{ Args: { "p_desde": string,"p_hasta": string }; Returns: {
              "a_convenir": number,"cancelados": number,"cancelados_pasajero": number,"completados": number,"fecha": string,"ingresos": number,"minutos_asignacion": number,"por_telefono": number,"sin_conductor": number,"solicitados": number
            }[]
                           },
"responder_oferta":
{ Args: { "p_aceptar": boolean,"p_oferta_id": number }; Returns: {
              "asignado_en": string | null,
"canal": Database["public"]['Enums']["canal_viaje"],
"cancelado_en": string | null,
"cancelado_por": string | null,
"client_request_id": string | null,
"conductor_id": string | null,
"contacto_nombre": string | null,
"contacto_telefono": string | null,
"creado_por": string | null,
"destino": unknown,
"destino_lat": number | null,
"destino_lng": number | null,
"destino_referencia": string | null,
"estado": Database["public"]['Enums']["estado_viaje"],
"id": string,
"iniciado_en": string | null,
"llego_en": string | null,
"motivo_cancelacion": string | null,
"origen": unknown,
"origen_lat": number | null,
"origen_lng": number | null,
"origen_referencia": string | null,
"pasajero_id": string | null,
"sitio_id": number | null,
"solicitado_en": string,
"tarifa_monto": number | null,
"tarifa_recargo": number | null,
"terminado_en": string | null,
"unidad_id": number | null,
"zona_destino_id": number | null,
"zona_origen_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "viajes"
        isOneToOne: true
        isSetofReturn: false
      } },
"rol_actual":
{ Args: Record<PropertyKey, never>; Returns: Database["public"]['Enums']["rol_usuario"]
                           },
"sitio_actual":
{ Args: Record<PropertyKey, never>; Returns: number
                           },
"solicitar_viaje":
{ Args: { "p_client_request_id": string,"p_destino_lat"?: number,"p_destino_lng"?: number,"p_destino_referencia"?: string,"p_origen_lat": number,"p_origen_lng": number,"p_origen_referencia"?: string }; Returns: {
              "asignado_en": string | null,
"canal": Database["public"]['Enums']["canal_viaje"],
"cancelado_en": string | null,
"cancelado_por": string | null,
"client_request_id": string | null,
"conductor_id": string | null,
"contacto_nombre": string | null,
"contacto_telefono": string | null,
"creado_por": string | null,
"destino": unknown,
"destino_lat": number | null,
"destino_lng": number | null,
"destino_referencia": string | null,
"estado": Database["public"]['Enums']["estado_viaje"],
"id": string,
"iniciado_en": string | null,
"llego_en": string | null,
"motivo_cancelacion": string | null,
"origen": unknown,
"origen_lat": number | null,
"origen_lng": number | null,
"origen_referencia": string | null,
"pasajero_id": string | null,
"sitio_id": number | null,
"solicitado_en": string,
"tarifa_monto": number | null,
"tarifa_recargo": number | null,
"terminado_en": string | null,
"unidad_id": number | null,
"zona_destino_id": number | null,
"zona_origen_id": number | null
            }
                          SetofOptions: {
        from: "*"
        to: "viajes"
        isOneToOne: true
        isSetofReturn: false
      } },
"tarifa_estimada":
{ Args: { "destino_lat"?: number,"destino_lng"?: number,"momento"?: string,"origen_lat": number,"origen_lng": number }; Returns: {
              "monto": number,"monto_base": number,"nocturno": boolean,"recargo": number,"zona_destino": string,"zona_destino_id": number,"zona_origen": string,"zona_origen_id": number
            }[]
                           },
"zona_de":
{ Args: { "p": unknown }; Returns: number
                           }
          }
          Enums: {
            "canal_viaje": "app"|"telefono","estado_conductor": "fuera_de_servicio"|"disponible"|"ocupado","estado_viaje": "buscando"|"asignado"|"conductor_llego"|"en_curso"|"completado"|"cancelado"|"sin_conductor","respuesta_oferta": "pendiente"|"aceptada"|"rechazada"|"expirada"|"soltada","rol_usuario": "pasajero"|"conductor"|"despachador"|"admin"
          }
          CompositeTypes: {
            [_ in never]: never
          }
        }
}

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
  ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R
    }
    ? R
    : never
  : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I
    }
    ? I
    : never
  : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
  ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U
    }
    ? U
    : never
  : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
  ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
  ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never

export const Constants = {
  "graphql_public": {
          Enums: {
            
          }
        },"public": {
          Enums: {
            "canal_viaje": ["app", "telefono"],"estado_conductor": ["fuera_de_servicio", "disponible", "ocupado"],"estado_viaje": ["buscando", "asignado", "conductor_llego", "en_curso", "completado", "cancelado", "sin_conductor"],"respuesta_oferta": ["pendiente", "aceptada", "rechazada", "expirada", "soltada"],"rol_usuario": ["pasajero", "conductor", "despachador", "admin"]
          }
        }
} as const
