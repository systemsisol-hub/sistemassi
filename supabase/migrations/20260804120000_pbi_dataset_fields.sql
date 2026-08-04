-- Habilita que el asistente IA consulte los datos de un reporte de Power BI.
--
-- Contexto: los enlaces de powerbi_links son embeds públicos ("Publicar en la web"),
-- cuyo token no da acceso a los datos. Para leer el dataset hay que llamar a la API REST
-- de Power BI, que necesita el par workspace + dataset de cada reporte.
--
-- Workspace confirmado (tenant de SFKontrol, proveedor del ERP):
--   SISOL_KBI = 9d6868a1-526c-4aaf-9da9-0647e6cccef7
--
-- NO se rellenan valores aquí: la asignación reporte -> dataset debe salir de
-- GET /groups/{groupId}/reports, porque hay dos datasets de proveedores y el nombre
-- no basta para distinguirlos.

ALTER TABLE powerbi_links
  ADD COLUMN IF NOT EXISTS pbi_workspace_id uuid,
  ADD COLUMN IF NOT EXISTS pbi_dataset_id   uuid,
  ADD COLUMN IF NOT EXISTS ai_context       text;

COMMENT ON COLUMN powerbi_links.pbi_workspace_id IS
  'groupId del workspace de Power BI. Necesario para executeQueries.';
COMMENT ON COLUMN powerbi_links.pbi_dataset_id IS
  'datasetId del modelo semántico que alimenta el reporte. Obtener de GET /groups/{id}/reports.';
COMMENT ON COLUMN powerbi_links.ai_context IS
  'Descripción curada para el asistente: qué mide el reporte y cómo se calculan sus KPIs.';

-- Caché del esquema del modelo (tablas, columnas y medidas), para no re-descargarlo
-- en cada pregunta. La escribe y la lee únicamente la Edge Function con service role;
-- RLS activo sin políticas = inaccesible para los clientes.
CREATE TABLE IF NOT EXISTS pbi_model_cache (
  dataset_id  uuid PRIMARY KEY,
  schema_json jsonb       NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE pbi_model_cache ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE pbi_model_cache IS
  'Caché del esquema de modelos de Power BI. Solo accesible vía service role.';
