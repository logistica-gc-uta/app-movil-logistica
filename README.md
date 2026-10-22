# app-movil-logistica

App móvil en Flutter (Android) para el chofer del sistema de logística y entrega de pedidos. Consume la API del [backend](https://github.com/logistica-gc-uta/backend).

**Estado actual:** inicio de sesión del chofer, pantalla «Mi Ruta del Día» e «Iniciar ruta» implementados. El formulario de entregas fallidas y la confirmación de regreso al depósito (issue #8) siguen pendientes.

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

- **Contenido:** cada ruta muestra su zona, su estado y sus paradas ordenadas por `stopOrder`, con la dirección y el estado del pedido. El progreso usa el resultado persistido de la visita; una entrega posterior en otra ruta no convierte una visita fallida en exitosa. Solo las rutas antiguas sin visitas persistidas usan el estado comercial como respaldo.
- **Estados de pantalla:** cargando, error con botón «Reintentar» y «No tienes rutas para hoy». Se puede deslizar hacia abajo para actualizar. Si falla una recarga, se conserva la ruta consultada y se muestra el error. Si el servidor confirmó una mutación pero falla el GET posterior, se avisa que la lista no está actualizada.
- **Acciones:** con la ruta en curso (`IN_PROGRESS`), cada pedido ofrece «En camino» (`ASSIGNED` → `IN_TRANSIT`) y luego «Entregado» (`IN_TRANSIT` → `DELIVERED`) mediante `PATCH /orders/:id/status`. La lista se refresca después de que el servidor confirma el cambio; si el servidor lo rechaza, se muestra el motivo y no un éxito.
- **Iniciar ruta:** solo el chofer autenticado ve «Iniciar ruta» en sus rutas `ASSIGNED`. Envía `POST /routes/:id/start` con `{}`; el backend verifica rol, propiedad, reservas y estado. El botón muestra espera y bloquea otras acciones hasta recibir respuesta. Solo entonces se refleja `IN_PROGRESS` y la hora de inicio en Ecuador. La repetición autorizada conserva la hora original en el servidor.
- **Recuperación del inicio:** si se pierde la respuesta, se consulta GET sin reenviar automáticamente el POST. Si tampoco se puede consultar, es necesario actualizar la lista antes de otro intento. Un GET anterior que responda tarde no revierte un inicio confirmado. Los errores 403 y 409 se muestran como rechazos, sin anunciar éxito; un 401 con sesión activa vuelve al login.
- **Paradas y finalización:** con la ruta en curso se conserva el orden y se informa su bloqueo; la app no ofrece edición ni reordenamiento. `COMPLETED` indica visitas finalizadas y muestra que el chofer sigue ocupado/retornando hasta que exista confirmación persistida de regreso. Nunca se deduce `AVAILABLE` del estado de la ruta.

Para probarla hace falta una ruta asignada al chofer de prueba para el día de hoy (desde el panel web de administración o con los datos de demostración del backend).

### Bienvenida y colores

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

## Estructura

```
lib/
├── main.dart                  Punto de arranque: crea los servicios reales
├── app.dart                   Widget raíz: bienvenida, login o zona privada, y selector de colores
├── core/                      Código compartido por toda la app
│   ├── config/                AppConfig: URL base de la API
│   ├── network/               ApiClient (cliente HTTP) y ApiException
│   ├── theme/                 Tema visual, BrandColors y BrandStorage
│   └── widgets/               BrandWordmark (marca) y PrimaryButton
└── features/                  Una carpeta por funcionalidad
    ├── auth/
    │   ├── data/              AuthSession, SessionStorage, AuthService y OnboardingStorage
    │   └── presentation/      WelcomePage y LoginPage
    └── routes/
        ├── data/              DriverRoute (ruta y paradas) y RoutesService
        └── presentation/      MyRoutePage
test/                          Pruebas; replica la estructura de lib/
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

## Flujo de trabajo

1. Crea una rama desde `main` con prefijo `feat/`, por ejemplo `feat/auth-flutter`.
2. Haz tus cambios y confirma que pasan `flutter analyze` y `flutter test`.
3. Sube la rama y abre un Pull Request hacia `main` que incluya `Closes #N` con el número del issue.
4. No subas credenciales, tokens ni archivos `.env`.

## Problemas comunes

**`flutter devices` no muestra el teléfono.** Suele ser un cable USB de solo carga. Prueba con otro cable, revisa que aceptaste el aviso de depuración y que el modo USB sea «Transferencia de archivos».

**«No se pudo conectar con el servidor.» al iniciar sesión.** Revisa, en este orden: que el backend esté encendido; que la app se haya ejecutado con el `--dart-define=API_BASE_URL=...` correcto (en un teléfono físico el valor por defecto `10.0.2.2` no funciona); que el teléfono y el PC estén en la misma red Wi-Fi; y que el Firewall de Windows permita conexiones entrantes al puerto `3000`.

**`Could not read workspace metadata from ...\.gradle\caches\...\metadata.bin`.** La caché de Gradle quedó dañada, normalmente por cambiar de versión de JDK. Bórrala y vuelve a compilar:

```powershell
.\android\gradlew.bat --stop
Remove-Item -Recurse -Force "$env:USERPROFILE\.gradle\caches\8.14\transforms"
flutter run
```
