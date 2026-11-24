# app-movil-logistica

App móvil en Flutter (Android) para el chofer del sistema de logística y entrega de pedidos. Consume la API del [backend](https://github.com/logistica-gc-uta/backend).

**Estado actual:** inicio de sesión del chofer, «Mi Ruta del Día», «Iniciar ruta», registro de intentos fallidos, cierre de ruta y confirmación de regreso al depósito implementados. El APK de demostración y la conexión al staging se documentan en [APK de demostración](docs/apk-demo.md).

## Requisitos

| Herramienta | Versión probada |
|---|---|
| Flutter | 3.41.3, canal stable (Dart 3.11.1) |
| JDK | 17 |
| Android SDK | Plataforma 36, con las licencias aceptadas |
| Dispositivo | Emulador Android o teléfono con depuración USB |

Comprueba tu entorno con:

```powershell
flutter doctor -v
```

La sección `Android toolchain` debe salir con `[✓]`. El aviso de Visual Studio se puede ignorar: solo aplica a apps de escritorio Windows.

Si `flutter doctor` muestra otro JDK o licencias pendientes:

```powershell
flutter config --jdk-dir="C:\Program Files\Java\jdk-17"
flutter doctor --android-licenses
```

## Instalación

```powershell
git clone https://github.com/logistica-gc-uta/app-movil-logistica.git
cd app-movil-logistica
flutter pub get
```

## Ejecución

Con un emulador encendido o un teléfono conectado:

```powershell
flutter devices
flutter run
```

La primera compilación tarda varios minutos. Con la app abierta, en la terminal: `r` recarga los cambios, `R` reinicia y `q` sale.

### En emulador

```powershell
flutter emulators
flutter emulators --launch <id_del_emulador>
flutter run
```

### En teléfono físico

1. En el teléfono: **Ajustes → Acerca del teléfono** y toca 7 veces **Número de compilación** (en Xiaomi, **Versión de MIUI/HyperOS**).
2. En **Opciones de desarrollador** activa **Depuración por USB** (en Xiaomi, también **Instalar vía USB**).
3. Conecta el teléfono con un cable USB de datos y acepta el aviso de depuración.
4. Ejecuta `flutter devices` para confirmar que aparece y luego `flutter run`.

## URL de la API

La app lee la URL base de la variable de compilación `API_BASE_URL`. No hay URLs ni secretos fijos que cambiar en el código.

El backend local escucha en el puerto `3000` con el prefijo `/api/v1`.

| Dónde corre la app | URL base | Comando |
|---|---|---|
| Emulador Android | `http://10.0.2.2:3000/api/v1` (valor por defecto) | `flutter run` |
| Teléfono físico | `http://<IP_DEL_PC>:3000/api/v1` | `flutter run --dart-define=API_BASE_URL=http://<IP_DEL_PC>:3000/api/v1` |
| Servidor remoto | `https://<host>/api/v1` | `flutter run --dart-define=API_BASE_URL=https://<host>/api/v1` |

En lugar de escribir el `--dart-define` cada vez, puedes usar los archivos de entorno de [`config/`](config/): copia el `.example.json` correspondiente y ejecuta, por ejemplo, `flutter run --dart-define-from-file=config/lan.json`. Los `config/*.json` no se suben al repositorio.

Las builds **release** solo se conectan por HTTPS. Para compilar una release que use `http://` (emulador o red local) hay que añadir `ALLOW_INSECURE_HTTP=true`; si no, la app muestra un aviso de configuración y no pide la contraseña.

**No uses `localhost` ni `127.0.0.1`.** Dentro del emulador o del teléfono, `localhost` es el propio dispositivo, no tu PC.

- **Emulador:** `10.0.2.2` es la dirección especial con la que el emulador Android llega al PC donde corre.
- **Teléfono físico:** usa la IP del PC en la red local. Obtenla con `ipconfig` (campo **Dirección IPv4** del adaptador Wi-Fi). El teléfono y el PC deben estar en la misma red, y el Firewall de Windows debe permitir conexiones entrantes al puerto `3000`.

## Inicio de sesión

La app consume `POST /auth/login` y solo deja entrar a usuarios con rol `DRIVER`.

| Situación | Qué hace la app |
|---|---|
| Campos vacíos o correo sin `@` | Marca el error en el campo y no llama al servidor |
| Credenciales correctas de un `DRIVER` | Guarda la sesión y abre la zona privada |
| Credenciales correctas de un `ADMIN` o `CLIENT` | Muestra «Esta aplicación es solo para choferes.» y no guarda nada |
| Credenciales incorrectas (401) | Muestra «Correo o contraseña incorrectos.» |
| Sin conexión o sin respuesta en 15 s | Muestra «No se pudo conectar con el servidor.» |
| Token caducado (401 con sesión activa) | Cierra la sesión y vuelve al login con un aviso |

- **Sesión persistente:** el token y los datos del usuario se guardan cifrados con `flutter_secure_storage`. Al reabrir la app se recupera la sesión sin pedir la contraseña.
- **Peticiones autenticadas:** con sesión activa, `ApiClient` añade la cabecera `Authorization: Bearer <token>` a cada petición.
- **Cierre de sesión:** el botón de la barra superior borra la sesión guardada y el token.
- **Privacidad:** la app no escribe en los logs el token ni la contraseña, y la copia de seguridad de Android está desactivada (`android:allowBackup="false"`) para que el token no salga del teléfono.

## Mi Ruta del Día

Tras iniciar sesión, la app consulta `GET /drivers/me/routes?date=YYYY-MM-DD` con la fecha de hoy en Ecuador (UTC-5). El backend identifica al chofer por el token, así que nunca se ven rutas de otros choferes.

- **Contenido:** cada ruta muestra cuántas paradas tiene, su estado y su avance; las paradas van ordenadas por `stopOrder`, con la dirección y el resultado de cada visita. La app ya no maneja zonas. El progreso usa el resultado persistido de la visita; una entrega posterior en otra ruta no convierte una visita fallida en exitosa. Solo las rutas antiguas sin visitas persistidas usan el estado comercial como respaldo.
- **Navegación:** la pantalla principal muestra una tarjeta por ruta, con su estado y su avance. «Iniciar ruta» (o «Continuar ruta» / «Ver resumen» si ya empezó) abre la vista de paradas; en una ruta asignada, «Ver paradas» permite revisarlas antes de iniciar. «Regresar» o el botón atrás del teléfono vuelve a las rutas del día.
- **Fin de las paradas:** al confirmar «Entregado», la parada muestra «Entregado con éxito». Si era la última parada (entregada o con intento fallido), aparece una confirmación y la tarjeta de la ruta muestra «Paradas completadas» o, si hubo un intento fallido, «Paradas finalizadas» con el detalle, sin anunciar éxito total. La ruta sigue «En curso» hasta que el chofer la cierra.
- **Estados de pantalla:** cargando, error con botón «Reintentar» y «No tienes rutas para hoy». Se puede deslizar hacia abajo para actualizar. Si falla una recarga, se conserva la ruta consultada y se muestra el error. Si el servidor confirmó una mutación pero falla el GET posterior, se avisa que la lista no está actualizada.
- **Acciones:** con la ruta en curso (`IN_PROGRESS`), las paradas se atienden en orden y una a la vez. Solo la parada en turno ofrece «En camino» (`ASSIGNED` → `IN_TRANSIT`) y luego «Entregado» (`IN_TRANSIT` → `DELIVERED`) mediante `PATCH /orders/:id/status`; las demás muestran «Disponible al terminar la parada N». La parada en turno es la que ya va en camino o, si no hay, la primera pendiente; un intento fallido también la da por terminada. Esta regla la aplica la app: el backend acepta cualquier parada de la ruta. La lista se refresca después de que el servidor confirma el cambio; si el servidor lo rechaza, se muestra el motivo y no un éxito.
- **Iniciar ruta:** solo el chofer autenticado ve «Iniciar ruta» en sus rutas `ASSIGNED`. Envía `POST /routes/:id/start` con `{}`; el backend verifica rol, propiedad, reservas y estado. El botón muestra espera y bloquea otras acciones hasta recibir respuesta. Solo entonces se refleja `IN_PROGRESS` y la hora de inicio en Ecuador. La repetición autorizada conserva la hora original en el servidor.
- **Recuperación del inicio:** si se pierde la respuesta, se consulta GET sin reenviar automáticamente el POST. Si tampoco se puede consultar, es necesario actualizar la lista antes de otro intento. Un GET anterior que responda tarde no revierte un inicio confirmado. Los errores 403 y 409 se muestran como rechazos, sin anunciar éxito; un 401 con sesión activa vuelve al login.
- **Paradas y finalización:** con la ruta en curso la lista de paradas no cambia; la app no ofrece edición ni reordenamiento. Nunca se deduce `COMPLETED` ni `AVAILABLE` contando paradas: cada paso lo confirma el servidor.
- **No se pudo entregar:** la parada en turno ofrece registrar un intento fallido con motivo tipificado («Destinatario ausente» o «Rechazó el pedido») y una descripción obligatoria. Envía `POST /routes/:id/stops/:stopId/failure` con un `requestId` (UUID v4). El pedido no pasa a `CANCELLED` ni a `DELIVERED`: queda para que ADMIN decida si se reprograma. Si se pierde la respuesta se consulta GET; reenviar los mismos datos repite el `requestId`, que el servidor trata como repetición.
- **Cerrar ruta:** con todas las visitas resueltas, «Cerrar ruta» envía `POST /routes/:id/complete` con `{}` tras pedir confirmación. La ruta pasa a «Completada», pero el chofer sigue ocupado.
- **Confirmar llegada al depósito:** en una ruta `COMPLETED` o `INTERRUPTED` sin regreso, el chofer confirma su llegada con `POST /routes/:id/return`. La app no verifica la ubicación. El resumen de la ruta separa visitas resueltas, ruta cerrada, regreso y disponibilidad; esta última solo se muestra con la respuesta del servidor o al tocar «Consultar» (`GET /drivers/me/availability`).
- **Rutas interrumpidas:** una ruta interrumpida por la administración muestra su motivo, no ofrece acciones de parada y permite confirmar el regreso.

Para probarla hace falta una ruta asignada al chofer de prueba para el día de hoy (desde el panel web de administración o con los datos de demostración del backend).

### Bienvenida y colores

La zona privada comparte el lenguaje visual del inicio de sesión: fondo blanco, tipografía Inter con títulos pesados, superficies grises suaves y el negro como único color de acción. Solo los estados usan color: verde para lo entregado, rojo para los intentos fallidos y ámbar para los avisos. La parada en turno es un bloque negro con sus dos acciones («En camino» / «Entregado» y «No se pudo entregar»); las demás paradas son filas simples. Los estilos están en `lib/features/routes/presentation/route_style.dart` y los componentes en `route_card.dart`, `route_detail.dart`, `stop_tile.dart`, `route_dialogs.dart` y `route_parts.dart`.

- **Bienvenida:** la primera vez que se abre la app se muestra una pantalla de bienvenida. Al pulsar «Continuar» se guarda en el teléfono que ya se vio y no vuelve a aparecer, ni siquiera tras cerrar sesión. Para verla de nuevo hay que borrar los datos de la app (Ajustes → Apps → Almacenamiento → Borrar datos). Para revisar su diseño mientras desarrollas, ejecuta la app con `flutter run --dart-define=ALWAYS_SHOW_WELCOME=true` y aparecerá en cada arranque.
- **Invertir colores:** el botón «Invertir» de la esquina superior derecha intercambia el blanco y el negro de la bienvenida y del inicio de sesión. La elección se guarda en el teléfono.

### Probar contra el backend local

1. Levanta el backend siguiendo su [README](https://github.com/logistica-gc-uta/backend#readme), incluido el paso del *seed*, que crea los usuarios de prueba.
2. Comprueba desde el PC que responde: abre `http://localhost:3000/api/docs` en el navegador.
3. Ejecuta la app apuntando al backend, según la tabla de [URL de la API](#url-de-la-api). Por ejemplo, en un teléfono físico:

   ```powershell
   flutter run --dart-define=API_BASE_URL=http://<IP_DEL_PC>:3000/api/v1
   ```

4. Inicia sesión con los usuarios del *seed* (sección «Credenciales por Defecto» del README del backend): uno con rol `DRIVER` debe entrar; uno `ADMIN` o `CLIENT` debe ser rechazado.

## APK de demostración

```powershell
Copy-Item config/staging.example.json config/staging.json   # y completa la URL
.	ooluild_demo_apk.ps1 -Environment staging
```

Genera en `build/demo/` un APK release nombrado con versión, entorno y commit, su SHA-256 y un archivo con los datos de la build. La app muestra esa identificación en la bienvenida y el login. La configuración por entorno, la firma, la instalación, el guion de la demo, el plan alternativo sin conexión y las limitaciones están en [docs/apk-demo.md](docs/apk-demo.md). La evidencia de la issue #6 está en [docs/evidence/issue-6](docs/evidence/issue-6/README.md).

## Estructura

```
lib/
├── main.dart                  Punto de arranque: crea los servicios reales
├── app.dart                   Widget raíz: bienvenida, login o zona privada, y selector de colores
├── core/                      Código compartido por toda la app
│   ├── config/                AppConfig (URL de la API, entorno, build) y ConfigErrorApp
│   ├── network/               ApiClient (cliente HTTP) y ApiException
│   ├── theme/                 Tema visual, BrandColors y BrandStorage
│   └── widgets/               BrandWordmark (marca) y PrimaryButton
└── features/                  Una carpeta por funcionalidad
    ├── auth/
    │   ├── data/              AuthSession, SessionStorage, AuthService y OnboardingStorage
    │   └── presentation/      WelcomePage y LoginPage
    └── routes/
        ├── data/              DriverRoute (ruta, paradas, disponibilidad) y RoutesService
        └── presentation/      MyRoutePage y sus componentes (route_style, route_card, route_detail, stop_tile…)
test/                          Pruebas; replica la estructura de lib/
config/                        Ejemplos de configuración por entorno (*.example.json)
tool/                          build_demo_apk.ps1 y fixture aislada para integración
assets/fonts/                  Tipografía Inter (licencia OFL)
```

Las pantallas no llaman al paquete `http` directamente: usan `ApiClient`, que antepone la URL base, decodifica el JSON y lanza `ApiException` cuando el servidor responde con error. Las reglas del login (rol, mensajes, guardado) están en `AuthService`, no en la pantalla.

## Calidad

Antes de cada Pull Request deben pasar sin errores:

```powershell
flutter pub get
flutter analyze
flutter test
```

Las reglas de análisis están en `analysis_options.yaml`. Las pruebas usan un servidor y un almacenamiento simulados, así que no necesitan backend ni dispositivo.

La prueba adicional `integration_test/daily_route_test.dart` usa Android, NestJS y PostgreSQL reales con una base aislada y datos ficticios. Ver [evidencia y reproducción de la issue #3](docs/evidence/issue-3/README.md).

El inicio explícito, la repetición idempotente y la ruta completada con retorno pendiente se validan con `integration_test/start_route_test.dart`. Ver [evidencia y reproducción de la issue #4](docs/evidence/issue-4/README.md).

El avance muestra por separado el porcentaje de entregas exitosas y las visitas resueltas. Si se pierde la respuesta de una entrega, se recupera el estado mediante GET sin reenviar la mutación; si también falla la consulta, se conserva la ruta y se bloquean cambios hasta actualizar. Se puede usar el icono «Actualizar estado», deslizar para recargar o volver a la app. La recuperación en primer plano requiere actualización manual. Ver [pruebas y reproducción de la issue #5](docs/evidence/issue-5/README.md), incluidos los contratos REST de fallo/retorno cuya interfaz corresponde a #8.

El intento fallido, el cierre de ruta y la confirmación de regreso se validan desde la interfaz con `integration_test/failed_visit_return_test.dart`, contra NestJS y PostgreSQL reales. Ver [evidencia y reproducción de la issue #8](docs/evidence/issue-8/README.md).

## Flujo de trabajo

Cada issue se resuelve en su propia rama y entra a `main` solo mediante un Pull Request revisado.

1. **Rama.** Actualiza `main` y crea una rama con el tipo de cambio como prefijo:

   ```powershell
   git checkout main
   git pull
   git checkout -b feat/driver-failed-visit
   ```

   | Prefijo | Uso | Ejemplo |
   |---|---|---|
   | `feat/` | Funcionalidad nueva | `feat/driver-start-route` |
   | `fix/` | Corrección de un error | `fix/login-timeout` |
   | `test/` | Pruebas o evidencia | `test/issue-5-progress-recovery` |
   | `chore/` | Configuración, herramientas o documentación | `chore/github-pr-template` |

2. **Commits.** Mensajes con el formato `tipo(ámbito): descripción`, por ejemplo `feat(driver): iniciar ruta con confirmación REST`. Termina el cuerpo con `Refs #N`.
3. **Validación.** Antes de subir, deben pasar sin errores:

   ```powershell
   flutter pub get
   flutter analyze
   flutter test
   ```

   Si el cambio afecta pantallas o llamadas a la API, pruébalo también en un emulador o teléfono contra el backend, incluidos los errores de red (sin conexión, timeout y respuestas 401/403/409). Guarda la evidencia en `docs/evidence/issue-N/`.
4. **Pull Request.** Sube la rama (`git push -u origin <rama>`) y abre el PR hacia `main`. GitHub carga automáticamente la [plantilla](.github/pull_request_template.md): completa la descripción, la tabla de pruebas, el dispositivo y la API usados, las evidencias y el checklist.
5. **Enlace con el issue.** Escribe `Closes #N` solo si el PR completa el issue: al fusionarlo, GitHub lo cierra automáticamente. Si lo resuelve en parte, usa `Refs #N` y explica qué falta.
6. **Revisión.** Pide revisión a otro integrante del equipo y atiende sus comentarios en la misma rama. Fusiona solo cuando el PR esté aprobado y la validación haya pasado.

**Nunca subas** credenciales, tokens, archivos `.env`, `config/*.json` locales, `android/key.properties` ni keystores. Las capturas y los logs del PR deben usar datos de prueba ficticios y no mostrar tokens ni contraseñas.

## Problemas comunes

**`flutter devices` no muestra el teléfono.** Suele ser un cable USB de solo carga. Prueba con otro cable, revisa que aceptaste el aviso de depuración y que el modo USB sea «Transferencia de archivos».

**«No se pudo conectar con el servidor.» al iniciar sesión.** Revisa, en este orden: que el backend esté encendido; que la app se haya ejecutado con el `--dart-define=API_BASE_URL=...` correcto (en un teléfono físico el valor por defecto `10.0.2.2` no funciona); que el teléfono y el PC estén en la misma red Wi-Fi; y que el Firewall de Windows permita conexiones entrantes al puerto `3000`.

**`Could not read workspace metadata from ...\.gradle\caches\...\metadata.bin`.** La caché de Gradle quedó dañada, normalmente por cambiar de versión de JDK. Bórrala y vuelve a compilar:

```powershell
.\android\gradlew.bat --stop
Remove-Item -Recurse -Force "$env:USERPROFILE\.gradle\caches\8.14\transforms"
flutter run
```
