-- =====================================================================
-- Auditoría genérica (una sola tabla) para el catálogo de datos
-- Destino: tasa_dev_trusted.fedel_sandbox
-- Tablas auditadas: domain, subdomain, collection, collection_owner, collection_table
-- =====================================================================

CREATE TABLE IF NOT EXISTS tasa_dev_trusted.fedel_sandbox.audit_log (
  audit_id             BIGINT    GENERATED ALWAYS AS IDENTITY,  -- PK única (clave real)
  table_name           STRING    NOT NULL,   -- qué tabla cambió
  record_pk            STRING    NOT NULL,   -- JSON con la PK (simple o compuesta)
  action               STRING    NOT NULL,   -- INSERT / UPDATE / DELETE
  changed_at           TIMESTAMP NOT NULL,   -- cuándo ocurrió
  changed_by_entra_id  STRING    NOT NULL,   -- actor (snapshot SCIM)
  changed_by_email     STRING,               -- actor legible (snapshot)
  old_values           STRING,               -- JSON estado anterior (NULL en INSERT)
  new_values           STRING                -- JSON estado nuevo    (NULL en DELETE)
)
USING DELTA
TBLPROPERTIES (
  delta.appendOnly = true,                    -- impide UPDATE/DELETE: log append-only
  delta.enableChangeDataFeed = false
);

-- Restricciones informativas (en Delta NO se fuerzan, documentan intención):
--   - action solo puede ser INSERT/UPDATE/DELETE
--   - table_name solo puede ser una de las 5 tablas auditadas
ALTER TABLE tasa_dev_trusted.fedel_sandbox.audit_log
  ADD CONSTRAINT chk_action CHECK (action IN ('INSERT','UPDATE','DELETE'));

ALTER TABLE tasa_dev_trusted.fedel_sandbox.audit_log
  ADD CONSTRAINT chk_table CHECK (table_name IN
    ('domain','subdomain','collection','collection_owner','collection_table'));


-- =====================================================================
-- EJEMPLOS DE ESCRITURA (en la misma transacción que la op. de negocio)
-- =====================================================================

-- 1) PK simple: UPDATE de una collection
INSERT INTO tasa_dev_trusted.fedel_sandbox.audit_log
  (table_name, record_pk, action, changed_at, changed_by_entra_id, changed_by_email, old_values, new_values)
VALUES (
  'collection',
  to_json(named_struct('collection_id', 4217)),
  'UPDATE',
  current_timestamp(),
  'admin-99-entra', 'admin@empresa.com',
  to_json(named_struct('status','inactive','is_published',false)),  -- antes
  to_json(named_struct('status','active','is_published',true))       -- después
);

-- 2) PK compuesta: INSERT en collection_owner
INSERT INTO tasa_dev_trusted.fedel_sandbox.audit_log
  (table_name, record_pk, action, changed_at, changed_by_entra_id, changed_by_email, old_values, new_values)
VALUES (
  'collection_owner',
  to_json(named_struct('collection_id', 4217, 'owner_entra_id', 'a1b2-entra')),
  'INSERT',
  current_timestamp(),
  'admin-99-entra', 'admin@empresa.com',
  NULL,                                                              -- INSERT: sin old
  to_json(named_struct('collection_id',4217,'owner_entra_id','a1b2-entra','owner_email','juan.perez@empresa.com'))
);

-- 3) PK compuesta: DELETE en collection_table
INSERT INTO tasa_dev_trusted.fedel_sandbox.audit_log
  (table_name, record_pk, action, changed_at, changed_by_entra_id, changed_by_email, old_values, new_values)
VALUES (
  'collection_table',
  to_json(named_struct('collection_id', 4217, 'data_table_id', 88)),
  'DELETE',
  current_timestamp(),
  'admin-99-entra', 'admin@empresa.com',
  to_json(named_struct('collection_id',4217,'data_table_id',88)),    -- último estado
  NULL                                                               -- DELETE: sin new
);


-- =====================================================================
-- EJEMPLOS DE CONSULTA
-- =====================================================================

-- Historial completo de una collection (PK simple)
SELECT audit_id, action, changed_at, changed_by_email, old_values, new_values
FROM tasa_dev_trusted.fedel_sandbox.audit_log
WHERE table_name = 'collection'
  AND record_pk:collection_id = 4217        -- acceso a campo JSON, sin parsear strings
ORDER BY changed_at;

-- Historial de un owner puntual (PK compuesta)
SELECT action, changed_at, changed_by_email
FROM tasa_dev_trusted.fedel_sandbox.audit_log
WHERE table_name = 'collection_owner'
  AND record_pk:collection_id  = 4217
  AND record_pk:owner_entra_id = 'a1b2-entra'
ORDER BY changed_at;

-- Todos los owners auditados de una collection (filtra por un solo campo del JSON)
SELECT record_pk:owner_entra_id AS owner, action, changed_at
FROM tasa_dev_trusted.fedel_sandbox.audit_log
WHERE table_name = 'collection_owner'
  AND record_pk:collection_id = 4217
ORDER BY changed_at;

-- Quién hizo cambios en las últimas 24 h, sobre cualquiera de las 5 tablas
SELECT table_name, action, record_pk, changed_by_email, changed_at
FROM tasa_dev_trusted.fedel_sandbox.audit_log
WHERE changed_at >= current_timestamp() - INTERVAL 24 HOURS
ORDER BY changed_at DESC;
