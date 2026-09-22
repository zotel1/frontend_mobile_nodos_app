/// Configuración centralizada de la app Nodos.
///
/// Todas las constantes de protocolo BLE, thresholds de proximidad,
/// parámetros de duty cycling y configuraciones del modelo van en este archivo.
/// NINGÚN secreto (API keys, tokens) debe estar aquí — van en GitHub Secrets.
///
/// Convenciones:
/// - UUIDs propios para las características del protocolo Nodos.
/// - Valores en dBm para RSSI.
/// - Valores en segundos para duraciones.
/// - Documentar fuente/justificación de cada valor no trivial.
library;

// ──────────────────────── Protocolo Nodos ────────────────────────

/// Versión actual del protocolo de comunicación entre instalaciones Nodos.
///
/// La versión viaja dentro de los payloads que puedan evolucionar con el
/// tiempo. Permite que versiones futuras de la app detecten payloads
/// incompatibles sin depender de la versión de la APK.
const int nodosProtocolVersion = 1;

/// Shared Service UUID for BLE discovery.
///
/// Todos los dispositivos que ejecutan Nodos anuncian este UUID.
/// Identifica al protocolo Nodos y no a una instalación concreta.
///
/// No es un secreto.
const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

/// UUID de la característica de identidad Nodos.
///
/// Expone la identidad persistente de la instalación remota.
///
/// Payload actual:
///
/// ```json
/// {
///   "uuid": "...",
///   "name": "...",
///   "color": "..."
/// }
/// ```
///
/// Esta característica continúa separada del intercambio del grafo porque
/// la identidad es necesaria incluso cuando no se necesita consultar
/// relaciones.
///
/// Si el dispositivo remoto no ejecuta Nodos, esta característica no existe
/// y se utiliza el mecanismo de fallback correspondiente.
const String identityCharacteristicUUID =
    '4fafc202-1fb5-459e-8fcc-c5c9c331914b';

/// UUID de la característica mediante la cual el periférico Nodos publica
/// su snapshot de grafo activo.
///
/// Dirección principal:
///
/// ```text
/// Peripheral → Central
/// ```
///
/// IMPORTANTE:
///
/// - No transmite la base SQLite.
/// - No utiliza Node.id como identidad global.
/// - No retransmite relaciones recibidas de terceros.
/// - El propietario del payload es siempre la instalación que lo genera.
/// - Las relaciones representan el estado activo conocido por el propietario.
///
/// Ejemplo conceptual:
///
/// ```json
/// {
///   "protocolVersion": 1,
///   "ownerUuid": "...",
///   "connections": []
/// }
/// ```
const String graphCharacteristicUUID = '4fafc203-1fb5-459e-8fcc-c5c9c331914b';

/// UUID de la característica de control para el enlace entre dos
/// instalaciones Nodos.
///
/// Esta característica forma parte del handshake de FEAT-003.
///
/// El central escribe solicitudes de enlace:
///
/// ```text
/// Central → Peripheral
///          LinkRequest
/// ```
///
/// El periférico puede responder mediante notificación:
///
/// ```text
/// Peripheral → Central
///             LinkResponse
/// ```
///
/// El contenido concreto de LinkRequest y LinkResponse se define mediante
/// entidades versionadas del protocolo y no en esta capa de configuración.
///
/// Esta característica NO representa el bonding/pairing Bluetooth del sistema.
/// Es un enlace lógico propio de Nodos.
const String linkCharacteristicUUID = '4fafc204-1fb5-459e-8fcc-c5c9c331914b';

/// UUID de la característica utilizada por el central para entregar al
/// periférico su propio snapshot de grafo activo.
///
/// Dirección:
///
/// ```text
/// Central → Peripheral
/// ```
///
/// Complementa [graphCharacteristicUUID]:
///
/// ```text
/// graphCharacteristicUUID
/// Peripheral ───────────────► Central
///
/// peerGraphCharacteristicUUID
/// Peripheral ◄─────────────── Central
/// ```
///
/// El payload utiliza el mismo formato NodosGraphPayload.
///
/// El propietario indicado por ownerUuid debe ser la instalación que envía
/// el snapshot.
///
/// Recibir este payload NO convierte las relaciones reportadas en conexiones
/// locales persistentes. Deben conservarse como relaciones remotas/reportadas.
const String peerGraphCharacteristicUUID =
    '4fafc205-1fb5-459e-8fcc-c5c9c331914b';

// ──────────────────────── RSSI / proximidad ────────────────────────

/// RSSI de referencia asumido a 1 metro.
///
/// Utilizado por el modelo de estimación de distancia.
///
/// Este valor todavía debe calibrarse mediante mediciones reales.
const int txPower = -50;

/// RSSI threshold for "close" proximity (dBm).
const int proximityThresholdClose = -70;

/// RSSI threshold for "medium" proximity (dBm).
const int proximityThresholdMedium = -85;

/// RSSI threshold for "far" proximity — maximum range.
///
/// Devices below this RSSI are filtered out from scan results.
///
/// Relaxed from -85 (medium) to -95 to detect devices at greater
/// distance.
///
/// IMPORTANTE:
/// Los valores de distancia derivados de RSSI son aproximaciones y dependen
/// fuertemente del dispositivo y del entorno. Estos thresholds deben
/// calibrarse mediante pruebas reales.
const int proximityThresholdFar = -95;

/// Exponente de pérdida de trayectoria (n) para el modelo log-distance.
///
/// Usado en distance_calc.dart:
///
/// distancia = 10 ^ ((txPower - rssi) / (10 * pathLossExponent))
///
/// n = 2.0 representa aproximadamente propagación en espacio libre.
/// En interiores normalmente será necesario calibrarlo.
const double pathLossExponent = 2.0;

// ──────────────────────── BLE duty cycling ────────────────────────

/// Duración de cada período activo de escaneo BLE.
const Duration dutyCycleScanDuration = Duration(seconds: 2);

/// Pausa entre períodos activos de escaneo BLE.
const Duration dutyCyclePauseDuration = Duration(seconds: 8);
