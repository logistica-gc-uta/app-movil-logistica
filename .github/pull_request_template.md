## Descripción

Explica qué problema resuelve este Pull Request y qué ve el chofer en la app.

## Issue relacionado

Closes #NUMERO

<!-- Usa "Closes #N" solo si el PR completa el Issue. Si lo cubre en parte, usa "Refs #N" y di qué falta en "Limitaciones conocidas". -->

## Cambios realizados

- 
- 
- 

## Pruebas realizadas

| Prueba | Resultado | Evidencia |
|---|---|---|
| `flutter pub get` | | |
| `flutter analyze` | | |
| `flutter test` | | Total de pruebas aprobadas: |
| Compilación (`flutter build apk`) | | |
| Integración (`integration_test/`) | | |
| Prueba manual en emulador o teléfono | | |
| Errores de red (sin conexión, timeout, 401/403/409) | | |

Indicar N/A y justificar cuando una prueba no aplique (por ejemplo, un cambio solo de documentación no necesita compilación).

**Dispositivo usado:** <!-- Ej.: emulador Medium_Phone_API_36.1 (Android 16) o modelo del teléfono y versión de Android -->

**API usada:** <!-- Ej.: backend local por emulador (http://10.0.2.2:3000/api/v1), fixture aislada (puerto 3003) o staging HTTPS. Indica el commit del backend. Nunca pegues tokens ni contraseñas. -->

## Evidencias

Adjuntar capturas del emulador o teléfono, logs o enlaces, o la carpeta `docs/evidence/issue-N/`.

- Usar solo datos de prueba ficticios.
- **Nunca** mostrar tokens JWT, contraseñas, archivos `.env` o `config/*.json` reales, `android/key.properties`, datos reales de destinatarios ni paneles de administración del servidor.
- Si una captura muestra la consola o los logs, revisarla antes de subirla.

## Impacto técnico

**API / Contratos:** <!-- Endpoints que consume o cuyo uso cambia -->

**Configuración / Entornos:** <!-- Nuevos --dart-define, cambios en config/*.example.json, permisos Android, firma -->

**Seguridad y sesión:** <!-- Manejo del token, datos guardados en el teléfono, conexión HTTPS -->

**Compatibilidad con otros componentes:** <!-- Backend, panel web ADMIN -->

**Limitaciones conocidas:**

## Checklist de entrega

- [ ] Cumplí los criterios de aceptación del Issue.
- [ ] Implementé únicamente los cambios necesarios.
- [ ] `flutter analyze` sin problemas y `flutter test` aprobado.
- [ ] Probé la app en un emulador o teléfono real cuando el cambio afecta pantallas o red.
- [ ] Comprobé los errores de red y las respuestas de error del servidor que aplican.
- [ ] Actualicé el README o `docs/` cuando fue necesario.
- [ ] No incluí credenciales, tokens ni información sensible en el código, las capturas ni los logs.
- [ ] Adjunté evidencia de los resultados.
- [ ] Solicité revisión a otro integrante.

## Observaciones para el revisor

Indicar los puntos que requieren especial atención.
