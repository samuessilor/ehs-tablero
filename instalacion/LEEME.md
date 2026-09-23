# EHS — el tablero en este equipo

## Para usarlo

Doble clic en el ícono **EHS** del escritorio. Se abre el navegador con el tablero.
No hace falta abrir nada más: ni una consola, ni un puerto, ni un motor de base de
datos que arrancar a mano — todo eso ya está corriendo en segundo plano desde que
inicias sesión en Windows.

Cuatro pantallas. Las otras tres se abren desde la barra de arriba del tablero
(**Capturar mes**, **Consultar y corregir**, **Descargar reporte**):

| Pantalla | Para qué |
|---|---|
| **Tablero** | Los cinco indicadores del mes, contra su meta |
| **Capturar mes** | Entrar los 27 números del mes que acaba de cerrar. El tablero publica el mes cuando están los 27; donde no hay personal temporal se escribe 0 |
| **Consultar y corregir** | Arreglar un número que ya se capturó, con el motivo de por qué cambia |
| **Descargar reporte** | Un resumen para imprimir o guardar como PDF |

## Si algo no responde

Una franja en la parte de arriba de cada pantalla dice si el motor está conectado.
Si aparece en rojo, o si el ícono **EHS** abre una página que no carga:

1. Doble clic en el ícono **Reparar EHS** del escritorio.
2. Espera a que la ventana que se abre diga "Listo" y se cierre sola. Si Docker
   Desktop estaba cerrado, Reparar lo abre y lo espera: puede tardar un par de
   minutos.
3. Recarga el tablero (F5).

Si sigue en rojo después de reparar, la ventana de Reparar deja un mensaje en rojo:
ese mensaje, tal cual, es lo único que hace falta reportar.

Docker Desktop tiene que estar abierto para que el tablero funcione. Queda
configurado para abrirse solo al iniciar sesión: no hace falta cerrarlo nunca.

## Lo que nunca hace falta hacer

- No hay que instalar nada más.
- No hay que abrir una consola ni escribir un comando.
- No hay que hacer respaldo a mano: se hace solo, todos los días y después de cada
  captura o corrección, en `C:\EHS\ehs-datos\respaldo\` y, si OneDrive de la empresa
  está configurado en el equipo, también en la carpeta `EHS-respaldo` de OneDrive. La
  franja de arriba dice cuándo fue el último.
- No hay que recordar ninguna contraseña: el tablero ya sabe cómo conectarse.

## Una cosa importante sobre corregir

Cuando algo cambia en "Consultar y corregir", el valor anterior no se borra: queda
archivado junto con quién hizo el cambio, cuándo, y por qué (es obligatorio explicarlo
al corregir). El historial completo de correcciones está al final de esa misma
pantalla.
