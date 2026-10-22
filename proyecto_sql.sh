#!/bin/bash
# ============================================================
#  Proyecto SQL Server - Grupo 6
#  Servidor de base de datos de inventario
#  Script unico: crea la BD, usuarios, vistas, respaldo y
#  prueba de restauracion, todo de una sola ejecucion.
# ============================================================

# ---- CONFIGURACION: cambia la contrasena de sa por la tuya ----
SA_PASS='CAMBIA_ESTA_CLAVE'
SQLCMD='/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '"$SA_PASS"' -C'
BACKUP_DIR='/var/opt/mssql/backups'

echo "=============================================="
echo "  Proyecto SQL Server - Grupo 6"
echo "=============================================="

# ---- 1. Carpeta de respaldos ----
echo "[1/6] Creando carpeta de respaldos..."
sudo mkdir -p "$BACKUP_DIR"
sudo chown mssql:mssql "$BACKUP_DIR"

# ---- 2. Crear base de datos, tablas y datos ----
echo "[2/6] Creando base de datos y tablas..."
$SQLCMD -Q "
IF DB_ID('inventario') IS NOT NULL
BEGIN
  ALTER DATABASE inventario SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE inventario;
END
CREATE DATABASE inventario;
"

$SQLCMD -d inventario -Q "
-- Tabla de categorias
CREATE TABLE categorias (
  id INT PRIMARY KEY IDENTITY,
  nombre NVARCHAR(50) NOT NULL
);

-- Tabla de productos (relacionada con categorias)
CREATE TABLE productos (
  id INT PRIMARY KEY IDENTITY,
  nombre NVARCHAR(100) NOT NULL,
  cantidad INT NOT NULL,
  precio DECIMAL(10,2) NOT NULL,
  categoria_id INT FOREIGN KEY REFERENCES categorias(id)
);

-- Tabla de clientes
CREATE TABLE clientes (
  id INT PRIMARY KEY IDENTITY,
  nombre NVARCHAR(100) NOT NULL,
  correo NVARCHAR(100)
);

-- Tabla de ventas (relaciona clientes y productos)
CREATE TABLE ventas (
  id INT PRIMARY KEY IDENTITY,
  cliente_id INT FOREIGN KEY REFERENCES clientes(id),
  producto_id INT FOREIGN KEY REFERENCES productos(id),
  cantidad INT NOT NULL,
  fecha DATE DEFAULT GETDATE()
);
"

# ---- 3. Insertar datos de ejemplo ----
echo "[3/6] Insertando datos de ejemplo..."
$SQLCMD -d inventario -Q "
INSERT INTO categorias (nombre) VALUES
  ('Perifericos'), ('Computadoras'), ('Oficina');

INSERT INTO productos (nombre, cantidad, precio, categoria_id) VALUES
  ('Teclado', 50, 25.00, 1),
  ('Mouse', 100, 12.50, 1),
  ('Monitor', 20, 180.00, 1),
  ('Laptop', 15, 850.00, 2),
  ('Desktop', 10, 700.00, 2),
  ('Impresora', 8, 220.00, 3),
  ('Escritorio', 5, 150.00, 3);

INSERT INTO clientes (nombre, correo) VALUES
  ('Juan Perez', 'juan@correo.com'),
  ('Maria Gomez', 'maria@correo.com'),
  ('Carlos Ruiz', 'carlos@correo.com');

INSERT INTO ventas (cliente_id, producto_id, cantidad) VALUES
  (1, 4, 1),
  (2, 1, 3),
  (3, 3, 2);
"

# ---- 4. Usuarios con permisos minimos ----
echo "[4/6] Creando usuarios con permisos minimos..."
$SQLCMD -Q "
-- Usuario para la aplicacion: lee y escribe, no cambia estructura
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name='app_user')
  CREATE LOGIN app_user WITH PASSWORD = 'AppUser.2026!';
-- Usuario de solo lectura: para reportes
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name='lectura')
  CREATE LOGIN lectura WITH PASSWORD = 'Lectura.2026!';
"
$SQLCMD -d inventario -Q "
CREATE USER app_user FOR LOGIN app_user;
ALTER ROLE db_datareader ADD MEMBER app_user;
ALTER ROLE db_datawriter ADD MEMBER app_user;

CREATE USER lectura FOR LOGIN lectura;
ALTER ROLE db_datareader ADD MEMBER lectura;
"

# ---- 5. Vista y procedimiento almacenado ----
echo "[5/6] Creando vista y procedimiento..."
$SQLCMD -d inventario -Q "
-- Vista: productos con poco stock (menos de 15 unidades)
EXEC('CREATE VIEW stock_bajo AS
  SELECT nombre, cantidad FROM productos WHERE cantidad < 15');
"
$SQLCMD -d inventario -Q "
-- Procedimiento: agregar un producto nuevo
EXEC('CREATE PROCEDURE agregar_producto
  @nombre NVARCHAR(100), @cantidad INT, @precio DECIMAL(10,2), @cat INT
AS
  INSERT INTO productos (nombre, cantidad, precio, categoria_id)
  VALUES (@nombre, @cantidad, @precio, @cat)');
"

# ---- 6. Respaldo y prueba de restauracion ----
echo "[6/6] Respaldo y prueba de restauracion..."
$SQLCMD -Q "BACKUP DATABASE inventario TO DISK = '$BACKUP_DIR/inventario.bak' WITH FORMAT;"

echo "    -> Borrando un producto a proposito (Mouse)..."
$SQLCMD -d inventario -Q "DELETE FROM productos WHERE nombre='Mouse';"

echo "    -> Restaurando desde el respaldo..."
$SQLCMD -Q "
ALTER DATABASE inventario SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE inventario FROM DISK = '$BACKUP_DIR/inventario.bak' WITH REPLACE;
ALTER DATABASE inventario SET MULTI_USER;
"

# ============================================================
#  RESULTADOS: demostracion de que todo funciona
# ============================================================
echo ""
echo "=============================================="
echo "  RESULTADOS"
echo "=============================================="

echo ""
echo ">> Productos (el Mouse volvio tras la restauracion):"
$SQLCMD -d inventario -Q "SELECT id, nombre, cantidad, precio FROM productos;"

echo ""
echo ">> Reporte: ventas con nombre de cliente y producto (JOIN):"
$SQLCMD -d inventario -Q "
SELECT c.nombre AS cliente, p.nombre AS producto, v.cantidad, v.fecha
FROM ventas v
JOIN clientes c ON v.cliente_id = c.id
JOIN productos p ON v.producto_id = p.id;
"

echo ""
echo ">> Vista de productos con poco stock:"
$SQLCMD -d inventario -Q "SELECT * FROM stock_bajo;"

echo ""
echo ">> Usuarios creados en el servidor:"
$SQLCMD -Q "SELECT name AS usuario, type_desc AS tipo FROM sys.server_principals WHERE name IN ('sa','app_user','lectura');"

echo ""
echo "=============================================="
echo "  PROYECTO COMPLETADO CON EXITO"
echo "=============================================="
