# APK de demostración

Guía para compilar, identificar, instalar y presentar el APK del chofer. Cubre la issue #6.

## 1. Configurar el entorno

La app no tiene ninguna URL del servidor escrita en el código. Cada build recibe la suya desde un archivo `config/<entorno>.json`. Esos archivos no se suben al repositorio: se copian de los ejemplos y se completan en cada PC.

| Entorno | Archivo | URL típica | ¿Permite `http://`? |
|---|---|---|---|
| Emulador Android | `config/emulator.json` | `http://10.0.2.2:3000/api/v1` | Sí |
| Teléfono en la red local | `config/lan.json` | `http://<IP_DEL_PC>:3000/api/v1` | Sí |
| Staging (Coolify + Cloudflare Tunnel) | `config/staging.json` | `https://<dominio-api-staging>/api/v1` | **No** |

```powershell
Copy-Item config/staging.example.json config/staging.json
# Edita config/staging.json y reemplaza <dominio-api-staging> por el dominio real de la API.
```

Cada archivo define tres valores:

- `API_BASE_URL`: URL base de la API, terminada en `/api/v1`.
- `APP_ENV`: nombre del entorno. Solo identifica la build.
- `ALLOW_INSECURE_HTTP`: `"true"` únicamente para el emulador o la red local.

### Conexión segura

- Una build **release** solo se conecta por HTTPS. Si recibe `http://` sin `ALLOW_INSECURE_HTTP=true`, o una URL inválida o con usuario y contraseña dentro, muestra una pantalla de configuración y **no pide la contraseña**. Así las credenciales nunca viajan sin cifrar por error de configuración.
- El script de compilación también rechaza el staging si no usa HTTPS.
- El token JWT se guarda cifrado con `flutter_secure_storage`, la copia de seguridad de Android está desactivada y la app no escribe el token ni la contraseña en los logs.
- La URL de la API no es un secreto, pero tampoco se sube al repositorio: queda en `config/*.json`, que git ignora.

## 2. Compilar el APK identificado

```powershell
.\tool\build_demo_apk.ps1 -Environment staging
```

El script:

1. Valida `config/staging.json` (que exista, que no tenga el valor de ejemplo y que use HTTPS).
2. Exige que no haya cambios sin confirmar, para que el APK corresponda a un commit exacto. Con `-AllowDirty` compila igual, pero marca la build como `-dirty`.
3. Ejecuta `flutter build apk --release` con la configuración del entorno, el commit y la versión de `pubspec.yaml`.
4. Deja en `build/demo/`:
   - `speedrun-<versión>-<entorno>-<commit>.apk`
   - `….apk.sha256`, con el hash para comprobar el archivo.
   - `….txt`, con la versión, el entorno, el host de la API, el commit completo, la fecha UTC, la versión de Flutter, el tipo de firma y el SHA-256.

La app muestra la misma identificación (por ejemplo `v1.0.0+1 · staging · 1a2b3c4`) en la esquina superior izquierda de la bienvenida y del inicio de sesión, para que cada captura diga qué build se usó. En las builds de desarrollo (`flutter run`) no aparece.

Requisitos: Flutter 3.41.3 (Dart 3.11.1), JDK 17 y Android SDK 36. Ver [README](../README.md#requisitos).

### Firma

- **Sin `android/key.properties`**, el APK se firma con la clave debug del PC que lo compila. Sirve para la demo, pero no para publicarlo. Además, un APK firmado en otro PC no se instala encima: hay que desinstalar el anterior.
- **Con firma propia**, crea `android/key.properties` (git ya lo ignora junto con `*.jks` y `*.keystore`):

  ```properties
  storePassword=<contraseña del keystore>
  keyPassword=<contraseña de la clave>
  keyAlias=speedrun
  storeFile=<ruta al .jks, relativa a android/app>
  ```

  Nunca subas ni compartas ese archivo, el keystore ni sus contraseñas.

## 3. Instalar

```powershell
& C:/Android/Sdk/platform-tools/adb.exe install -r build/demo/<archivo>.apk
```

En un teléfono también se puede copiar el APK y abrirlo, con «Instalar apps desconocidas» habilitado. Comprueba el hash antes de instalar un APK recibido por otro medio:

```powershell
Get-FileHash build/demo/<archivo>.apk -Algorithm SHA256
```

## 4. Guion de la demostración

Usa solo datos de prueba ficticios. En las capturas no deben aparecer tokens, contraseñas, datos reales de destinatarios ni el panel de Coolify.

| Paso | Qué se muestra | Estado en la app |
|---|---|---|
| 0 | Bienvenida con la identificación de la build | Disponible |
| 1 | Login de un `DRIVER`; un `ADMIN` o `CLIENT` es rechazado | Disponible |
| 2 | Mi Ruta del Día con la ruta asignada | Disponible |
| 3 | (a) **Iniciar ruta** → «En curso» con la hora de inicio en Ecuador | Disponible |
| 4 | (b) **En camino** → **Entregado** en las paradas, con el progreso | Disponible |
| 5 | (c) Registrar un **intento fallido** con motivo | **Pendiente (#8)** |
| 6 | (d) Ruta `COMPLETED` al resolver todas las visitas | **Pendiente (#8)**: la app ya muestra `COMPLETED` si el servidor lo devuelve, pero aún no tiene el botón para cerrar la ruta |
| 7 | (e) **Confirmar regreso al depósito** y ver al chofer disponible | **Pendiente (#8)** |

Los pasos 5 a 7 dependen de la issue #8. El backend ya publica esos endpoints, pero la app aún no tiene sus controles. Hasta que #8 se integre, la demo los declara pendientes: no se simulan desde la app ni con llamadas manuales presentadas como si fueran la interfaz. La reprogramación de un pedido fallido se hace solo en el panel web ADMIN, nunca desde Flutter.

La app no usa GPS continuo ni calcula ETA. El camión animado de «En camino» es solo una ilustración.

### Para preparar los datos

El staging necesita un chofer de prueba con una ruta `ASSIGNED` para el día de la demo (hora de Ecuador). Se crea desde el panel web ADMIN: pedidos, confirmar la ruta y asignarla. Prepárala poco antes de presentar: una ruta iniciada no vuelve a `ASSIGNED`.

## 5. Plan alternativo sin conexión

Si el día de la demo falla el staging, el túnel o la red:

1. **Backend local**: levanta el backend en el PC y usa el APK `lan` (teléfono en la misma Wi-Fi) o el APK `emulator`. El flujo es el mismo; solo cambia la URL.
2. **Grabación previa**: graba antes la demo completa contra el staging, por ejemplo con `adb shell screenrecord /sdcard/demo.mp4` o con la grabación del emulador, y reprodúcela explicando que es una grabación.

Ninguna de las dos alternativas cambia la lógica de la app: no hay un «modo demo» con datos inventados.

## 6. Limitaciones conocidas

- Sin `android/key.properties`, el APK se firma con la clave debug.
- El APK es *fat* (todas las arquitecturas, unos 47 MB). Con `flutter build apk --split-per-abi` se reduce, pero se generan varios archivos.
- La app no observa la conectividad: al recuperar la red hay que deslizar para actualizar o tocar «Actualizar estado».
- No hay cola offline: una acción sin conexión no se guarda para después.
- El staging depende del Cloudflare Tunnel y del despliegue en Coolify (backend #16). Si el dominio cambia, hay que recompilar el APK con la nueva URL.
