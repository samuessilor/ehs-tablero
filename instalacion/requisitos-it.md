# EHS local — qué le pide este paquete a IT

Una sola cosa: **permiso para correr `instalar.ps1` una vez en el equipo del área,
con derechos de administrador local durante esa instalación.** Nada más. No pide
acceso a internet, no abre ningún puerto hacia afuera, no toca el dominio ni ninguna
política de grupo, y no deja una cuenta con privilegios corriendo después.

Esto vale para **los dos modos**, no solo el nativo: registrar la tarea programada
que arranca el tablero necesita un proceso elevado para poder escribirla, aunque
la tarea en sí después corra sin ningún privilegio especial — son dos preguntas
distintas (quién puede *crear* la tarea, y con qué privilegios *corre* después), y
solo la segunda tiene una respuesta sin admin.

## Qué instala, exactamente

| Elemento | Detalle |
|---|---|
| Motor de base de datos | SQL Server 2022 Express (motor nativo) **o** el mismo motor en un contenedor Docker/Podman — se elige al instalar, con `-Motor nativo` o `-Motor contenedor` |
| Dónde escucha | **Solo `127.0.0.1`**, en un puerto fijo elegido al instalar. Nunca en una interfaz de red, así que nunca pide una excepción al firewall de Windows |
| La aplicación | Node.js empaquetado dentro de la carpeta de instalación — no instala Node en el sistema, no toca el PATH |
| Arranque | Una tarea programada **por usuario**, oculta, disparada al iniciar sesión. No es un servicio de Windows y no corre con una cuenta de sistema |
| Dos logins SQL | `ehs_migrador` (crea y actualiza el esquema; nunca corre mientras la app está en uso) y `ehs_app` (solo lee, y solo puede ejecutar dos procedimientos concretos — ni `db_owner` ni `sa`) |
| Respaldo | Un archivo `.bak` diario, más uno después de cada captura, a una carpeta local que después se sincroniza a OneDrive corporativo — como cualquier otro documento del equipo |

## Qué NO hace

- No expone ningún puerto a la red.
- No requiere una cuenta de servicio de dominio.
- No modifica el registro más allá de la propia instalación del motor (modo nativo)
  o de Docker/Podman (modo contenedor), que siguen sus propios instaladores oficiales.
- No manda datos fuera del equipo salvo el respaldo a OneDrive corporativo, que ya es
  donde vive el resto de la información del área.
- No deja credenciales en texto plano fuera de `config\ehs.env`, un archivo local con
  los mismos permisos de acceso que cualquier otro archivo de configuración del equipo.

## Prerrequisito según el modo

- **Nativo**: el instalador de SQL Server 2022 Express (`SQL2022-SSEI-Expr.exe` o el
  medio que IT ya distribuya) tiene que estar accesible localmente — este paquete no
  lo descarga. `instalar.ps1 -Motor nativo` necesita su ruta.
- **Contenedor**: Docker Desktop o Podman ya instalado en el equipo. Si ninguno de los
  dos está disponible, usar el modo nativo.

## Migrar más adelante a la instancia de empresa

El esquema, las migraciones y el ejecutor (`scripts\migrar.js`) son exactamente los
mismos que se usarían contra un SQL Server de la empresa. Migrar es cambiar
`config\ehs.env` (servidor, credenciales) y correr `migrar.js` contra la base nueva —
no se reescribe una sola tabla ni una vista. Ver `docs\` para el detalle completo del
proceso ya evaluado.

## Contacto

Cualquier duda de esta instalación, con Samuel Galeano — el mismo canal por el que
llegó este paquete.
