# Auditoría del catálogo — tabla única `audit_log`

Diseño de auditoría con **una sola tabla genérica** para auditar las 5 tablas:
`domain`, `subdomain`, `collection`, `collection_owner`, `collection_table`.

DDL completo + ejemplos en [`audit_log.sql`](audit_log.sql).

## Esquema

| Columna | Tipo | Descripción |
|---|---|---|
| `audit_id` | `BIGINT` (identity) | **PK real / única** de la entrada. |
| `table_name` | `STRING` | Qué tabla cambió (una de las 5). |
| `record_pk` | `STRING` (JSON) | PK de la fila afectada, **estructurada en JSON**. |
| `action` | `STRING` | `INSERT` / `UPDATE` / `DELETE`. |
| `changed_at` | `TIMESTAMP` | Cuándo ocurrió. |
| `changed_by_entra_id` | `STRING` | Actor (snapshot SCIM). |
| `changed_by_email` | `STRING` | Actor legible (snapshot). |
| `old_values` | `STRING` (JSON) | Estado anterior (NULL en `INSERT`). |
| `new_values` | `STRING` (JSON) | Estado nuevo (NULL en `DELETE`). |

## Decisiones de diseño

### 1. `record_pk` como JSON (no string serializado)
Resuelve las PKs **compuestas** sin concatenar ni elegir separadores:

| Tabla | PK | `record_pk` |
|---|---|---|
| `domain` | `domain_id` | `{"domain_id":12}` |
| `subdomain` | `subdomain_id` | `{"subdomain_id":45}` |
| `collection` | `collection_id` | `{"collection_id":4217}` |
| `collection_owner` | `(collection_id, owner_entra_id)` | `{"collection_id":4217,"owner_entra_id":"a1b2-entra"}` |
| `collection_table` | `(collection_id, data_table_id)` | `{"collection_id":4217,"data_table_id":88}` |

Se consulta con la sintaxis de campo JSON de Databricks: `record_pk:collection_id = 4217`.

### 2. `(table_name, record_pk)` NO es `UNIQUE`
Es la **clave lógica** para agrupar/buscar el historial de una fila, pero no puede ser
única: una fila editada N veces produce N entradas. La unicidad la aporta `audit_id`.

### 3. Append-only
`TBLPROPERTIES (delta.appendOnly = true)` impide `UPDATE`/`DELETE` sobre el log a nivel
motor. Cada cambio es siempre una fila nueva.

### 4. Sin FK real
`record_pk` apunta a filas de tablas distintas, así que no hay FK (ni tendría sentido en
Delta, donde las FK no se fuerzan). La integridad la garantiza la aplicación.

## Reglas por acción

| `action` | `old_values` | `new_values` | `record_pk` |
|---|---|---|---|
| `INSERT` | NULL | estado nuevo | PK del nuevo registro |
| `UPDATE` | estado anterior | estado resultante | PK del registro |
| `DELETE` | último estado | NULL | PK del registro borrado |

## Cómo se puebla
En la **misma transacción** que la operación de negocio, la capa de datos de la app
inserta la fila en `audit_log`. Alternativa desacoplada: Delta Change Data Feed + un job
que vuelque los cambios (propagando el actor por otra vía).

## Por qué una sola tabla (y no 5 de historial)
- ✅ Un solo objeto, menos mantenimiento.
- ✅ Absorbe cambios de esquema de las tablas origen sin DDL nuevo.
- ✅ Consultas "cross-tabla" triviales (quién cambió qué en las últimas 24 h).
- ⚠️ Los valores viven en JSON (consultables con `:` pero no tipados como columnas).
