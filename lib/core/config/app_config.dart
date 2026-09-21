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

/// UUID de la característica de intercambio de grafo Nodos.
///
/// Permite que dos instalaciones de Nodos intercambien información sobre
/// las relaciones DIRECTAS conocidas por cada una.
///
/// IMPORTANTE:
///
/// - No transmite la base SQLite.
/// - No utiliza Node.id porque ese identificador es local a cada instalación.
/// - No retransmite relaciones transitivas recibidas de terceros.
/// - El propietario del payload es siempre la instalación que lo genera.
///
/// El payload exacto se modelará mediante una entidad dedicada del protocolo.
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
///
/// Las relaciones con dispositivos Nodos utilizarán su deviceUuid estable.
/// La representación de dispositivos BLE genéricos se definirá antes de
/// habilitar su intercambio entre instalaciones.
const String graphCharacteristicUUID = '4fafc203-1fb5-459e-8fcc-c5c9c331914b';

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
