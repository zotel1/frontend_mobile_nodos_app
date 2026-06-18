Plan Completo de Desarrollo: Aplicación BLE de Proximidad
Entiendo completamente el alcance del proyecto. Voy a entregar un análisis arquitectónico senior que cubra especificación funcional, análisis técnico, patrones de diseño, seguridad y roadmap detallado.

📋 ÍNDICE

Análisis Comparativo: React Native vs Flutter
Especificación Funcional Completa
Arquitectura Backend (Java Spring Boot)
Arquitectura Frontend (React Native)
Análisis de Viabilidad BLE
Patrones de Diseño y DDD
Estrategia de Seguridad
Análisis de Riesgos Técnicos
Roadmap por Fases
Escalabilidad y Limitaciones


1️⃣ ANÁLISIS COMPARATIVO: REACT NATIVE VS FLUTTER
Matriz de Evaluación
CriterioReact NativeFlutterGanadorBLE Supportreact-native-ble-plx (bueno)flutter_blue_plus (excelente)Flutter ✅Background TasksLimitado, complejoNativo, directoFlutter ✅iOS RestrictivoDesafíosMejor soporteFlutter ✅Android BLEBuenoExcelenteFlutter ✅Performance GráficosAceptableSuperiorFlutter ✅Comunidad Java/SpringMejor integraciónN/AReact Native ✅Curva AprendizajeModeradaMás empinadaReact Native ✅Documentación BLEMejorSimilarNeutralTamaño Bundle~25-30MB~20-25MBFlutter ✅MantenimientoMás inestableMás estableFlutter ✅
RECOMENDACIÓN: FLUTTER ✅
Justificación:

BLE es crítico en tu proyecto → Flutter tiene soporte nativo superior
iOS restrictivo → Flutter maneja mejor Bluetooth en background (entitlements)
Visualización 2D/Grafos → Flutter con fl_chart, graphview es más eficiente
Restricciones en segundo plano → Flutter iOS puede mantener scanning activo con proper entitlements
Escalabilidad de nodos → Mejor performance renderizando múltiples nodos

Nota: Tu backend en Java Spring Boot es agnóstico del cliente. Funciona igual con Flutter o React Native. La elección de Flutter optimiza la experiencia en el lado que más lo necesita: el móvil con BLE.

2️⃣ ESPECIFICACIÓN FUNCIONAL COMPLETA
2.1 Flujo General de Datos
┌─────────────────────────────────────────────────────────────┐
│                    DISPOSITIVO MÓVIL                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐         ┌──────────────────┐          │
│  │   BLE Scanning   │         │  BLE Advertising │          │
│  │  (Periférico)    │         │   (Central)      │          │
│  └────────┬─────────┘         └────────┬─────────┘          │
│           │                            │                     │
│           └────────────┬───────────────┘                     │
│                        │                                     │
│              ┌─────────▼────────┐                            │
│              │  Detección Local │                            │
│              │  (Otros nodos)   │                            │
│              └────────┬─────────┘                            │
│                       │                                      │
│          ┌────────────┼────────────┐                         │
│          │            │            │                        │
│    ┌─────▼──┐  ┌─────▼──┐  ┌─────▼──┐                       │
│    │ Cache  │  │Historial│  │ Config │                      │
│    │ Local  │  │  Local  │  │ Nodo   │                      │
│    └────────┘  └────────┘  └────────┘                       │
│          │            │            │                        │
│          └────────────┼────────────┘                         │
│                       │                                      │
│              ┌────────▼──────────┐                           │
│              │ UI Layer (Grafos) │                           │
│              └─────────┬─────────┘                           │
│                        │                                     │
│         ┌──────────────┴──────────────┐                      │
│         │                             │                     │
│    [Botón Sincronizar]          [Mostrar Red]               │
│         │                             │                     │
│         └──────────────┬──────────────┘                      │
│                        │                                     │
│              [Con Internet disponible]                       │
│              [Obtener config de backend]                     │
│                                                              │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       │ HTTP/REST
                       │
           ┌───────────▼──────────┐
           │  Backend Java/Spring │
           │     (Render)         │
           ├──────────────────────┤
           │  - User Registry     │
           │  - Node Directory    │
           │  - Sync Service      │
           │  - PostgreSQL        │
           └──────────────────────┘
2.2 Casos de Uso Principales
Caso de Uso 1: Iniciar Aplicación (Offline)
Precondición: Dispositivo con datos locales previos
Flujo:
  1. App inicia
  2. Carga UUID Bluetooth del dispositivo
  3. Carga config local (nombre, color)
  4. Inicia BLE Scanning automáticamente
  5. Detecta nodos cercanos
  6. Renderiza UI con nodos conocidos/desconocidos
  7. Mantiene historial local
Caso de Uso 2: Sincronización Manual
Precondición: Conexión a Internet
Flujo:
  1. Usuario presiona "Sincronizar"
  2. App envía UUID al backend
  3. Backend retorna:
     - Datos del usuario (nombre, color actualizado)
     - Directorio global de nodos registrados
     - Última fecha de sincronización
  4. App actualiza cache local
  5. Muestra confirmación
Caso de Uso 3: Detectar Nodo Cercano
Precondición: BLE Scanning activo
Flujo:
  1. BLE detects nearby device advertising
  2. App calcula RSSI → distancia
  3. Consulta cache local por UUID
  4. Si existe:
     - Obtiene nombre, color, tipo dispositivo
     - Renderiza con color intenso (< 3m) / difuminado (> 3m)
  5. Si no existe:
     - Muestra "Nodo desconocido"
     - Color gris
  6. Actualiza historial (timestamp, RSSI, duración)
Caso de Uso 4: Vista Administrador (Mesh)
Precondición: Nodo A detecta B, B detecta C, C detecta D
Flujo:
  1. Usuario abre "Vista Administrador"
  2. App construye grafo local:
     - A es "yo"
     - B es detectado directamente por A
     - C es conocido por B (info compartida)
     - D es conocido por C (info compartida)
  3. Renderiza árbol jerárquico
  4. Intenta contactar B para obtener datos de C, D

3️⃣ ARQUITECTURA BACKEND (Java Spring Boot)
3.1 Arquitectura Hexagonal + DDD
┌────────────────────────────────────────────────────────────┐
│                    PRESENTACIÓN (REST)                      │
├────────────────────────────────────────────────────────────┤
│  POST /api/v1/auth/register                                │
│  GET  /api/v1/users/{uuid}                                 │
│  GET  /api/v1/nodes/directory                              │
│  POST /api/v1/sync/{uuid}                                  │
│  POST /api/v1/history/record                               │
│  GET  /api/v1/mesh/topology                                │
└────────────────────────────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
┌─────────────▼──────────┐   ┌─────────▼──────────┐
│  Application Services  │   │  DTOs / Mappers    │
│  (Casos de Uso)        │   │  (Validación)      │
└───────────┬────────────┘   └────────────────────┘
            │
┌───────────▼──────────────────────────────────────┐
│        CAPA DE DOMINIO (DDD)                      │
├───────────────────────────────────────────────────┤
│                                                   │
│  ┌──────────────────┐   ┌──────────────────┐    │
│  │ User Aggregate   │   │ Node Aggregate   │    │
│  │ ─────────────    │   │ ────────────     │    │
│  │ - UUID (ID)      │   │ - UUID (ID)      │    │
│  │ - name           │   │ - name           │    │
│  │ - color          │   │ - color          │    │
│  │ - deviceType     │   │ - deviceType     │    │
│  │ - created_at     │   │ - registered_at  │    │
│  │ - last_sync      │   │ - discoveredBy[] │    │
│  │                  │   │                  │    │
│  │ Commands:        │   │ Commands:        │    │
│  │ - RegisterUser   │   │ - RegisterNode   │    │
│  │ - UpdateUser     │   │ - UpdateMetadata │    │
│  │ - SyncUser       │   │ - RecordDiscovery│    │
│  └──────────────────┘   └──────────────────┘    │
│                                                   │
│  Domain Events:                                   │
│  - UserRegistered                                │
│  - UserSynced                                    │
│  - NodeDiscovered                                │
│  - SyncCompleted                                 │
│                                                   │
└───────────┬──────────────────────────────────────┘
            │
┌───────────▼────────────────────────────────────┐
│      CAPA DE APLICACIÓN (Repositories)         │
├──────────────────────────────────────────────┤
│                                                │
│  UserRepository (interfaz)                     │
│  NodeRepository (interfaz)                     │
│  HistoryRepository (interfaz)                  │
│  SyncRepository (interfaz)                     │
│                                                │
└───────────┬────────────────────────────────────┘
            │
┌───────────▼────────────────────────────────────┐
│      CAPA DE INFRAESTRUCTURA (JPA)            │
├──────────────────────────────────────────────┤
│                                                │
│  UserRepositoryJPA extends JpaRepository      │
│  NodeRepositoryJPA extends JpaRepository      │
│  HistoryRepositoryJPA extends JpaRepository   │
│  SyncRepositoryJPA extends JpaRepository      │
│                                                │
│  ┌────────────────────────────────────┐      │
│  │   POSTGRESQL (Supabase)            │      │
│  │   - users                          │      │
│  │   - nodes                          │      │
│  │   - contact_history                │      │
│  │   - sync_logs                      │      │
│  │   - topology_cache                 │      │
│  └────────────────────────────────────┘      │
│                                                │
└────────────────────────────────────────────────┘
3.2 Definición de Agregados (DDD)
Agregado 1: User
yamlUser:
  AggregateRoot:
    - id: UUID (Bluetooth UUID)
    - name: String
    - color: HexColor (#FF5733)
    - deviceType: Enum(ANDROID, iOS)
    - registeredAt: LocalDateTime
    - lastSyncAt: LocalDateTime
    - isActive: Boolean
    
  Value Objects:
    - BluetoothUUID: String (35 chars)
    - UserColor: String (validar hex)
    - DeviceType: Enum
    
  Repository: UserRepository
  Factory: UserFactory
  
  Domain Events:
    - UserRegisteredEvent(uuid, name, color, deviceType)
    - UserSyncedEvent(uuid, timestamp)
    - UserUpdatedEvent(uuid, changes)
Agregado 2: Node (Descubierto)
yamlDiscoveredNode:
  AggregateRoot:
    - id: UUID
    - name: String (o null si desconocido)
    - color: HexColor (o #808080 si desconocido)
    - deviceType: Enum (o null si desconocido)
    - discoveredBy: UUID (quién lo detectó)
    - discoveredAt: LocalDateTime
    - rssi: Integer (-100 to -30 dBm)
    - distance: Float (calculado from RSSI)
    - isKnown: Boolean
    
  Repository: DiscoveredNodeRepository
  
  Domain Events:
    - NodeDiscoveredEvent(discoveredBy, nodeUUID, rssi)
    - NodeLostSignalEvent(nodeUUID)
    - NodeMetadataUpdatedEvent(nodeUUID, name, color)
Agregado 3: Contact History
yamlContactHistory:
  AggregateRoot:
    - id: UUID (generated)
    - userA: UUID
    - userB: UUID
    - firstContactAt: LocalDateTime
    - lastContactAt: LocalDateTime
    - totalDuration: Long (milliseconds)
    - contactCount: Integer
    - averageRSSI: Float
    - history: List<ContactRecord>
    
  Value Objects:
    - ContactRecord:
      - timestamp: LocalDateTime
      - rssi: Integer
      - distance: Float
      
  Repository: ContactHistoryRepository
Agregado 4: Sync State
yamlSyncState:
  - userId: UUID
  - lastSyncAt: LocalDateTime
  - lastSyncVersion: Integer
  - nodeCount: Integer
  - status: Enum(SYNCED, PENDING, FAILED)
  - errorMessage: String (nullable)
3.3 Servicios de Aplicación (Use Cases)
java// Servicio 1: Registro de Usuario
RegisterUserService:
  - Command: RegisterUserCommand(uuid, name, color, deviceType)
  - Response: RegisterUserResponse(uuid, success, message)
  - Operaciones:
    * Validar UUID unique
    * Crear User Aggregate
    * Persistir en DB
    * Publicar UserRegisteredEvent
    * Retornar respuesta

// Servicio 2: Sincronización
SyncUserService:
  - Command: SyncUserCommand(uuid, lastSyncVersion)
  - Response: SyncUserResponse(uuid, nodes[], version, timestamp)
  - Operaciones:
    * Obtener User del repo
    * Cargar todos los Nodes registrados
    * Filtrar públicos/accesibles
    * Mapear a DTOs
    * Publicar UserSyncedEvent
    * Retornar directorio actualizado

// Servicio 3: Registrar Descubrimiento
RecordNodeDiscoveryService:
  - Command: RecordDiscoveryCommand(discoveredBy, nodeUUID, rssi)
  - Response: RecordDiscoveryResponse(success)
  - Operaciones:
    * Validar que ambos UUIDs existan en DB
    * Obtener/crear ContactHistory
    * Registrar ContactRecord
    * Calcular distancia from RSSI
    * Publicar NodeDiscoveredEvent
    * Retornar confirmación

// Servicio 4: Obtener Topología de Mesh
GetMeshTopologyService:
  - Command: GetTopologyCommand(nodeUUID, depth)
  - Response: MeshTopologyResponse(topology[], edges[])
  - Operaciones:
    * BFS/DFS desde nodeUUID
    * Obtener contactos directos (depth=1)
    * Obtener contactos secundarios (depth=2)
    * Construir grafo
    * Retornar JSON serializable

4️⃣ ARQUITECTURA FRONTEND (Flutter)
4.1 Estructura de Carpetas
lib/
├── main.dart
├── config/
│   ├── app_config.dart
│   ├── routes.dart
│   └── theme.dart
│
├── core/
│   ├── constants/
│   │   ├── ble_constants.dart
│   │   ├── ui_constants.dart
│   │   └── error_messages.dart
│   │
│   ├── errors/
│   │   ├── failures.dart
│   │   ├── exceptions.dart
│   │   └── error_handler.dart
│   │
│   ├── utils/
│   │   ├── logger.dart
│   │   ├── validators.dart
│   │   └── extensions.dart
│   │
│   └── services/
│       ├── secure_storage.dart
│       ├── local_db.dart
│       └── connectivity_service.dart
│
├── features/
│   │
│   ├── ble/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── ble_device.dart
│   │   │   │   ├── ble_scan_result.dart
│   │   │   │   └── rssi_to_distance.dart
│   │   │   │
│   │   │   ├── datasources/
│   │   │   │   ├── ble_datasource.dart (interfaz)
│   │   │   │   └── flutter_blue_datasource.dart
│   │   │   │
│   │   │   ├── repositories/
│   │   │   │   ├── ble_repository.dart (interfaz)
│   │   │   │   └── ble_repository_impl.dart
│   │   │   │
│   │   │   └── local_db/
│   │   │       ├── node_dao.dart
│   │   │       └── contact_history_dao.dart
│   │   │
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── scanned_node.dart
│   │   │   │   ├── node_metadata.dart
│   │   │   │   └── proximity_level.dart
│   │   │   │
│   │   │   ├── repositories/
│   │   │   │   └── ble_repository.dart (interfaz de dominio)
│   │   │   │
│   │   │   └── usecases/
│   │   │       ├── start_ble_scan_usecase.dart
│   │   │       ├── stop_ble_scan_usecase.dart
│   │   │       ├── get_nearby_nodes_usecase.dart
│   │   │       └── calculate_distance_usecase.dart
│   │   │
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── ble_scan_bloc.dart
│   │       │   ├── ble_scan_event.dart
│   │       │   ├── ble_scan_state.dart
│   │       │   ├── nearby_nodes_bloc.dart
│   │       │   ├── nearby_nodes_event.dart
│   │       │   └── nearby_nodes_state.dart
│   │       │
│   │       ├── widgets/
│   │       │   ├── node_widget.dart
│   │       │   ├── node_avatar.dart
│   │       │   ├── proximity_indicator.dart
│   │       │   └── signal_strength_indicator.dart
│   │       │
│   │       └── pages/
│   │           ├── home_page.dart
│   │           ├── network_view_page.dart
│   │           └── admin_view_page.dart
│   │
│   ├── sync/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── sync_request.dart
│   │   │   │   └── sync_response.dart
│   │   │   │
│   │   │   ├── datasources/
│   │   │   │   ├── remote_datasource.dart
│   │   │   │   └── remote_datasource_impl.dart
│   │   │   │
│   │   │   └── repositories/
│   │   │       └── sync_repository_impl.dart
│   │   │
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── sync_result.dart
│   │   │   │   └── node_directory.dart
│   │   │   │
│   │   │   ├── repositories/
│   │   │   │   └── sync_repository.dart
│   │   │   │
│   │   │   └── usecases/
│   │   │       ├── sync_user_usecase.dart
│   │   │       └── get_node_directory_usecase.dart
│   │   │
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── sync_bloc.dart
│   │       │   ├── sync_event.dart
│   │       │   └── sync_state.dart
│   │       │
│   │       └── widgets/
│   │           ├── sync_button.dart
│   │           └── sync_status_indicator.dart
│   │
│   ├── user/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   │   └── local_user_datasource.dart
│   │   │   │
│   │   │   └── repositories/
│   │   │       └── user_repository_impl.dart
│   │   │
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── user_profile.dart
│   │   │   │   └── device_info.dart
│   │   │   │
│   │   │   ├── repositories/
│   │   │   │   └── user_repository.dart
│   │   │   │
│   │   │   └── usecases/
│   │   │       ├── get_user_profile_usecase.dart
│   │   │       ├── init_local_user_usecase.dart
│   │   │       └── get_device_uuid_usecase.dart
│   │   │
│   │   └── presentation/
│   │       ├── bloc/
│   │       │   ├── user_bloc.dart
│   │       │   ├── user_event.dart
│   │       │   └── user_state.dart
│   │       │
│   │       └── pages/
│   │           ├── profile_page.dart
│   │           └── settings_page.dart
│   │
│   └── visualization/
│       ├── data/
│       │   └── models/
│       │       ├── graph_node.dart
│       │       └── graph_edge.dart
│       │
│       ├── domain/
│       │   ├── entities/
│       │   │   ├── network_graph.dart
│       │   │   └── visualization_mode.dart
│       │   │
│       │   └── usecases/
│       │       ├── build_network_graph_usecase.dart
│       │       └── calculate_node_positions_usecase.dart
│       │
│       └── presentation/
│           ├── bloc/
│           │   ├── visualization_bloc.dart
│           │   ├── visualization_event.dart
│           │   └── visualization_state.dart
│           │
│           ├── widgets/
│           │   ├── simple_view.dart (< 4 nodes)
│           │   ├── graph_view.dart (> 4 nodes)
│           │   ├── animated_node.dart
│           │   └── proximity_ring.dart
│           │
│           └── painters/
│               ├── network_graph_painter.dart
│               └── proximity_gradient_painter.dart
│
└── shared/
    ├── models/
    │   ├── api_response.dart
    │   └── pagination.dart
    │
    ├── widgets/
    │   ├── error_widget.dart
    │   ├── loading_widget.dart
    │   └── custom_app_bar.dart
    │
    └── providers/
        ├── dio_provider.dart
        └── local_db_provider.dart
4.2 Patrones de Presentación: BLoC
dart// Ejemplo: BLE Scan BLoC

class BleScanBloc extends Bloc<BleScanEvent, BleScanState> {
  final StartBLEScanUseCase startBLEScanUseCase;
  final StopBLEScanUseCase stopBLEScanUseCase;
  final GetNearbyNodesUseCase getNearbyNodesUseCase;
  
  StreamSubscription? _scanSubscription;
  
  BleScanBloc({
    required this.startBLEScanUseCase,
    required this.stopBLEScanUseCase,
    required this.getNearbyNodesUseCase,
  }) : super(BleScanInitial()) {
    on<StartBleScanEvent>(_onStartScan);
    on<StopBleScanEvent>(_onStopScan);
    on<BleDeviceFoundEvent>(_onDeviceFound);
    on<BleErrorEvent>(_onError);
  }
  
  Future<void> _onStartScan(
    StartBleScanEvent event,
    Emitter<BleScanState> emit,
  ) async {
    emit(BleScanning());
    
    final result = await startBLEScanUseCase();
    
    result.fold(
      (failure) => emit(BleScanError(failure.message)),
      (scanStream) {
        _scanSubscription = scanStream.listen(
          (scannedNode) {
            add(BleDeviceFoundEvent(scannedNode));
          },
          onError: (error) {
            add(BleErrorEvent(error.toString()));
          },
        );
        emit(BleScanning());
      },
    );
  }
  
  Future<void> _onDeviceFound(
    BleDeviceFoundEvent event,
    Emitter<BleScanState> emit,
  ) async {
    final currentState = state;
    
    if (currentState is BleScanning) {
      final updatedNodes = List<ScannedNode>.from(currentState.nearbyNodes)
        ..add(event.scannedNode);
      
      emit(BleScanning(nearbyNodes: updatedNodes));
    }
  }
  
  @override
  Future<void> close() {
    _scanSubscription?.cancel();
    return super.close();
  }
}

5️⃣ ANÁLISIS DE VIABILIDAD TÉCNICA: BLE5.1 Limitaciones Reales de BLE
AspectoLímiteImpacto en tu ProyectoRango máximo~240m (open space, -100dBm)Proximidad en evento: OK; en ciudad: limitadoVelocidad scan100-200 dispositivos/min500+ usuarios requiere múltiples pasadasConcurrent connections~7-10 periféricos simultáneos1000 usuarios: escenarios puntualesBattery drain5-15% por hora (scanning)Requiere optimización (duty cycle)Throughput240 Kbps (BLE 4.2) / 2 Mbps (BLE 5.x)Suficiente para metadatos pequeñosLatency en advertencia20-1280ms (según intervalo)Detectar nuevo nodo: 20-5 segundosPayload advertising31 bytes (BLE 4.2) / 251 bytes (BLE 5.x)Enviar solo UUID + RSSI offsetiOS background time~10 segundos (si no conectado)Requiere special entitlementsAndroid background scanSin restricción (con permisos)Mejor que iOS
5.2 Estrategia RSSI → Distancia
RSSI (Received Signal Strength Indicator) = -dBm

Fórmula de Friis modificada (Path Loss Model):
distance(m) = 10^((Tx Power - RSSI) / (10 * n))

Donde:
- Tx Power: típicamente -5 a 0 dBm (depende dispositivo)
- RSSI: valor medido (-100 a -30 dBm)
- n: índice de path loss (2-4):
  * 2.0 = open space
  * 2.5 = interior
  * 3.5 = obstáculos
  * 4.0 = muchos obstáculos

Simplificación para tu proyecto:
distance = 10^((-RSSI + 50) / 20)

Rangos propuestos:
- RSSI > -70 dBm  → < 3m (nodo definido, color intenso)
- RSSI -70 a -85 → 3-6m (nodo difuminado)
- RSSI < -85 dBm  → > 6m (nodo apenas visible)
5.3 Optimización de Batería
yamlEstrategia:
  1. Duty Cycle:
     - Scan 2 segundos
     - Pausa 8 segundos
     - Resultado: 20% duty cycle
     - Consumo: ~1% batería/hora
  
  2. Filtrado de Advertising:
     - Solo conectar si RSSI > -85 dBm
     - Ignorar dispositivos lejanos
     - Reducir procesamiento
  
  3. Background Mode (iOS):
     - Usar NSBluetoothPeripheralUsageDescription
     - Pedir permiso "Privacy - Bluetooth Peripheral Usage"
     - Limitar a 10 segundos en background
     - Reactivar cada vez que detecte cambios
  
  4. Android:
     - BLUETOOTH_SCAN con android:usesPermissionFlags="neverForLocation"
     - Evitar location-based tracking
     - Usar BroadcastReceiver para eventos Bluetooth
  
  5. Adaptación Dinámica:
     - Si batería < 20%: aumentar duty cycle a 40%
     - Si batería < 10%: desactivar BLE completamente
     - Usuario puede configurar agresividad
5.4 Bluetooth Mesh: Viabilidad
Opción 1: Solo Backend (NO Mesh)
Pros:
  ✅ Simple de implementar
  ✅ Sincronización clara
  ✅ Sin limitaciones BLE
  ✅ Escalable fácilmente

Contras:
  ❌ Requiere internet para topología completa
  ❌ Latencia en descubrimiento
  ❌ Costo de transferencia de datos

Implementación:
  - Cada dispositivo envía al backend: "detecté a X"
  - Backend construye grafo global
  - Dispositivos consultan backend para topología
Opción 2: Sincronización Local (Gossip Protocol)
Pros:
  ✅ Funciona offline
  ✅ Descubrimiento más rápido
  ✅ Menor carga backend

Contras:
  ⚠️ Complejidad media
  ⚠️ Posibles loops/duplicados
  ⚠️ Eventual consistency

Implementación:
  - A detecta B
  - A se conecta a B (BLE GATT)
  - A pregunta: "¿A quiénes detectaste?"
  - B responde: [C, D, E]
  - A actualiza su cache local
  - Próxima sincronización: A envía a backend
Opción 3: Bluetooth Mesh (Recomendado para Fase 6)
Pros:
  ✅ Verdadera malla: A <-> B <-> C
  ✅ Alcance extendido
  ✅ Autorretransmisión automática
  ✅ Escalable a miles de nodos

Contras:
  ❌ MUY complejo de implementar
  ❌ Librería oficial: solo Android (Mesh SDK oficial)
  ❌ iOS: no existe API nativa para Mesh
  ❌ Basado en Bluetooth 5.0+
  ❌ Consumo energético superior
  ❌ Latencia de 100-500ms por hop
  ❌ Requiere certificación Bluetooth SIG

Opciones técnicas:
  1. Usar nRF Mesh SDK (Nordic Semiconductor)
     - Android: soportado
     - iOS: port no oficial (riesgoso)
  
  2. Usar Thread/OpenThread + Bluetooth
     - Mejor interoperabilidad
     - Mejor soporte iOS
     - Diferente stack (no es Mesh)
  
  3. Implementación custom (Gossip mejorado)
     - Simular mesh con GATT + republishing
     - Control de TTL
     - Prevención de loops
     - Viable en MVP
Opción 4: Híbrida (RECOMENDADA) ✅
Fases 1-4: Backend + Sincronización Local
  - Cada dispositivo detecta BLE localmente
  - Comparte info con backend cuando hay internet
  - Gossip protocol simple para expandir cache
  - Visualiza hasta 50 nodos sin problema

Fase 5-6: Preparar Bluetooth Mesh
  - Investigar nRF Mesh SDK
  - Prototipo en Android
  - Estudio de viabilidad iOS
  - Arquitectura que permita plug-and-play

Roadmap Mesh:
  - Año 1: Backend + Local Gossip
  - Año 2: Mesh opcional en Android
  - Año 3+: Mesh iOS si es viable

6️⃣ PATRONES DE DISEÑO Y DDD
6.1 Patrones a Implementar
1. Repository Pattern
dart// Interfaz (Dominio)
abstract class NodeRepository {
  Future<Either<Failure, List<Node>>> getAllNodes();
  Future<Either<Failure, Node>> getNodeByUUID(String uuid);
  Future<Either<Failure, void>> saveNode(Node node);
}

// Implementación (Infraestructura)
class NodeRepositoryImpl implements NodeRepository {
  final NodeRemoteDataSource remoteDataSource;
  final NodeLocalDataSource localDataSource;
  final NetworkInfo networkInfo;
  
  @override
  Future<Either<Failure, List<Node>>> getAllNodes() async {
    if (await networkInfo.isConnected) {
      try {
        final remoteNodes = await remoteDataSource.getAllNodes();
        await localDataSource.cacheNodes(remoteNodes);
        return Right(remoteNodes);
      } catch (e) {
        return Left(ServerFailure());
      }
    } else {
      try {
        final localNodes = await localDataSource.getNodes();
        return Right(localNodes);
      } catch (e) {
        return Left(CacheFailure());
      }
    }
  }
}
2. Use Case Pattern (Clean Architecture)
dartabstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

class SyncUserUseCase extends UseCase<SyncResult, SyncParams> {
  final UserRepository userRepository;
  final SyncRepository syncRepository;
  
  SyncUserUseCase({
    required this.userRepository,
    required this.syncRepository,
  });
  
  @override
  Future<Either<Failure, SyncResult>> call(SyncParams params) async {
    final userOrFailure = await userRepository.getUserProfile();
    
    return userOrFailure.fold(
      (failure) => Left(failure),
      (user) async {
        try {
          final result = await syncRepository.syncUser(user);
          return Right(result);
        } catch (e) {
          return Left(NetworkFailure());
        }
      },
    );
  }
}
3. Value Object Pattern (DDD)
dart// Value Object: Color (inmutable, sin identidad)
class NodeColor extends Equatable {
  final String hexValue;
  
  const NodeColor(this.hexValue);
  
  factory NodeColor.fromString(String value) {
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(value)) {
      throw InvalidColorException();
    }
    return NodeColor(value);
  }
  
  @override
  List<Object?> get props => [hexValue];
}

// Value Object: Proximity Distance
class ProximityDistance extends Equatable {
  final double meters;
  
  const ProximityDistance(this.meters);
  
  factory ProximityDistance.fromRSSI(int rssi) {
    final distance = pow(10, ((-rssi + 50) / 20)).toDouble();
    return ProximityDistance(distance);
  }
  
  ProximityLevel get level {
    if (meters < 3) return ProximityLevel.CLOSE;
    if (meters < 6) return ProximityLevel.MEDIUM;
    return ProximityLevel.FAR;
  }
  
  @override
  List<Object?> get props => [meters];
}
4. Domain Event Pattern
dart// Evento de Dominio
abstract class DomainEvent extends Equatable {
  final DateTime occurredAt;
  
  DomainEvent({DateTime? occurredAt})
    : occurredAt = occurredAt ?? DateTime.now();
}

class NodeDiscoveredEvent extends DomainEvent {
  final String discoveredByUUID;
  final String nodeUUID;
  final int rssi;
  final String? nodeName;
  final String? nodeColor;
  
  NodeDiscoveredEvent({
    required this.discoveredByUUID,
    required this.nodeUUID,
    required this.rssi,
    this.nodeName,
    this.nodeColor,
    DateTime? occurredAt,
  }) : super(occurredAt: occurredAt);
  
  @override
  List<Object?> get props => [
    discoveredByUUID,
    nodeUUID,
    rssi,
    nodeName,
    nodeColor,
    occurredAt,
  ];
}

// EventPublisher (Bus)
abstract class DomainEventPublisher {
  void publish(DomainEvent event);
}

class InMemoryEventPublisher implements DomainEventPublisher {
  final List<DomainEvent> _events = [];
  final StreamController<DomainEvent> _eventStream =
    StreamController<DomainEvent>.broadcast();
  
  @override
  void publish(DomainEvent event) {
    _events.add(event);
    _eventStream.add(event);
  }
  
  Stream<DomainEvent> get eventStream => _eventStream.stream;
}
5. Specification Pattern (para queries complejas)
dart// Para consultas tipo: "dame todos los nodos cercanos (< 3m) y conocidos"
abstract class Specification<T> {
  bool isSatisfiedBy(T candidate);
  Specification<T> and(Specification<T> other);
  Specification<T> or(Specification<T> other);
}

class NearbyNodeSpecification extends Specification<ScannedNode> {
  static const PROXIMITY_THRESHOLD = 3.0; // metros
  
  @override
  bool isSatisfiedBy(ScannedNode node) {
    return node.distance.meters < PROXIMITY_THRESHOLD;
  }
  
  @override
  Specification<ScannedNode> and(Specification<ScannedNode> other) =>
    AndSpecification(this, other);
  
  @override
  Specification<ScannedNode> or(Specification<ScannedNode> other) =>
    OrSpecification(this, other);
}

class KnownNodeSpecification extends Specification<ScannedNode> {
  @override
  bool isSatisfiedBy(ScannedNode node) {
    return node.isKnown == true;
  }
  
  @override
  Specification<ScannedNode> and(Specification<ScannedNode> other) =>
    AndSpecification(this, other);
  
  @override
  Specification<ScannedNode> or(Specification<ScannedNode> other) =>
    OrSpecification(this, other);
}

// Uso
final spec = NearbyNodeSpecification()
  .and(KnownNodeSpecification());

final nearbyKnownNodes = allNodes
  .where((node) => spec.isSatisfiedBy(node))
  .toList();

7️⃣ ESTRATEGIA DE SEGURIDAD
7.1 Modelo de Seguridad
┌─────────────────────────────────────────────────────────┐
│                    CAPAS DE SEGURIDAD                    │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  LAYER 1: TRANSPORTE (BLE)                              │
│  ─────────────────────────────────────────             │
│  - BLE se encripta automáticamente (AES-CCM)           │
│  - Emparejamiento opcional (si es crítico)             │
│  - Validación de advertising data                       │
│                                                           │
│  LAYER 2: COMUNICACIÓN BACKEND (HTTP/REST)             │
│  ─────────────────────────────────────────             │
│  - HTTPS/TLS 1.3 obligatorio                           │
│  - Certificate Pinning                                  │
│  - JWT tokens (no stateless en este caso)              │
│                                                           │
│  LAYER 3: AUTENTICACIÓN (API)                          │
│  ─────────────────────────────────────────             │
│  - UUID Bluetooth como identidad primaria              │
│  - Device Fingerprinting (hardware info hash)          │
│  - Rate limiting por UUID                              │
│                                                           │
│  LAYER 4: DATOS (DB & LOCAL)                           │
│  ─────────────────────────────────────────             │
│  - Encriptación en reposo (Supabase)                   │
│  - Encriptación local (Flutter Secure Storage)         │
│  - No guardar datos sensibles en caché sin encriptar    │
│                                                           │
│  LAYER 5: LÓGICA DE NEGOCIO                            │
│  ─────────────────────────────────────────             │
│  - Validar que UUID del request = token holder         │
│  - Rate limiting: 10 sync/min por usuario              │
│  - Timeout de sesión                                   │
│  - Auditoría de operaciones críticas                   │
│                                                           │
└─────────────────────────────────────────────────────────┘
7.2 Autenticación sin Contraseña
yamlEstrategia: "Authentication by Device"

Flujo:
  1. Primer uso:
     - App genera UUID (usando device_info)
     - UUID = Hardware ID hash (Android: Build.SERIAL, iOS: NSUUID)
     - Envía: POST /api/v1/auth/register
       {
         "uuid": "550e8400-e29b-41d4-a716-446655440000",
         "name": "Mi teléfono",
         "color": "#FF5733",
         "deviceType": "ANDROID",
         "deviceFingerprint": "hash(IMEI+Model+OS)"
       }
     - Backend retorna: registration_token (JWT)
     
  2. Próximos usos (con internet):
     - App envía UUID en header Authorization
     - Backend valida:
       * UUID existe en DB
       * DeviceFingerprint coincide
       * Último sync < 30 días
     - Retorna datos actualizados + nuevo JWT
     
  3. Offline:
     - App funciona sin token
     - Usa caché local
     - Próximo sync: actualiza

Riesgos:
  - UUID puede ser spoofed (atenuado con fingerprinting)
  - No hay logout real (mitigado con caducidad token)
  - Robo de dispositivo = compromiso (problema fundamental)
7.3 Implementación de Seguridad en Código
Backend (Java Spring Boot)
java// 1. Security Config
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf().disable()
            .authorizeRequests()
                .antMatchers("/api/v1/auth/register").permitAll()
                .antMatchers("/api/v1/**").authenticated()
                .anyRequest().authenticated()
            .and()
            .addFilterBefore(
                new JWTAuthenticationFilter(),
                UsernamePasswordAuthenticationFilter.class
            )
            .sessionManagement()
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS);
        
        return http.build();
    }
    
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}

// 2. JWT Token Provider
@Component
public class JWTTokenProvider {
    
    @Value("${app.jwtSecret}")
    private String secretKey;
    
    @Value("${app.jwtExpirationMs:86400000}")
    private long expirationTime;
    
    public String generateToken(String uuid) {
        return Jwts.builder()
            .setSubject(uuid)
            .setIssuedAt(new Date())
            .setExpiration(new Date(System.currentTimeMillis() + expirationTime))
            .signWith(SignatureAlgorithm.HS512, secretKey)
            .compact();
    }
    
    public String getUUIDFromToken(String token) {
        return Jwts.parser()
            .setSigningKey(secretKey)
            .parseClaimsJws(token)
            .getBody()
            .getSubject();
    }
    
    public boolean validateToken(String token) {
        try {
            Jwts.parser().setSigningKey(secretKey).parseClaimsJws(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            return false;
        }
    }
}

// 3. Validación de Device Fingerprint
@Component
public class DeviceFingerprintValidator {
    
    public boolean validate(String uuid, String fingerprint) {
        // Obtener el fingerprint guardado de BD
        User user = userRepository.findByUUID(uuid);
        
        if (user == null) return false;
        
        // Comparar con hash actual
        String hashAct = hashDeviceInfo(fingerprint);
        return user.getDeviceFingerprintHash().equals(hashAct);
    }
    
    private String hashDeviceInfo(String fingerprint) {
        return DigestUtils.sha256Hex(fingerprint);
    }
}

// 4. Rate Limiting
@Component
@Aspect
public class RateLimitingAspect {
    
    private final RateLimiter limiter =
        RateLimiter.create(10.0); // 10 requests per second
    
    @Before("@annotation(RateLimit)")
    public void checkRateLimit(JoinPoint point) {
        String uuid = getCurrentUUID();
        
        if (!limiter.tryAcquire(uuid.hashCode())) {
            throw new RateLimitExceededException();
        }
    }
}

// 5. Endpoint de Registro
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    
    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(
        @RequestBody RegisterRequest request
    ) {
        // Validar que UUID sea válido
        if (!isValidUUID(request.getUuid())) {
            return ResponseEntity.badRequest().build();
        }
        
        // Crear o actualizar usuario
        User user = userService.registerOrUpdate(
            request.getUuid(),
            request.getName(),
            request.getColor(),
            request.getDeviceType(),
            request.getDeviceFingerprint()
        );
        
        // Generar token
        String token = jwtTokenProvider.generateToken(request.getUuid());
        
        return ResponseEntity.ok(
            new AuthResponse(token, user.getUuid(), user.getName())
        );
    }
}
Frontend (Flutter)
dart// 1. Secure Storage
class SecureTokenManager {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  static const _tokenKey = 'auth_token';
  static const _uuidKey = 'device_uuid';
  static const _fingerprintKey = 'device_fingerprint';
  
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }
  
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }
  
  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }
  
  Future<String> getUUID() async {
    String? uuid = await _secureStorage.read(key: _uuidKey);
    
    if (uuid == null) {
      uuid = await _generateUUID();
      await _secureStorage.write(key: _uuidKey, value: uuid);
    }
    
    return uuid;
  }
  
  Future<String> _generateUUID() async {
    final deviceInfo = DeviceInfoPlugin();
    String fingerprint;
    
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      fingerprint =
        '${androidInfo.model}${androidInfo.serialNumber}${androidInfo.id}';
    } else {
      final iosInfo = await deviceInfo.iosInfo;
      fingerprint =
        '${iosInfo.model}${iosInfo.systemVersion}${iosInfo.identifierForVendor}';
    }
    
    return _hashUUID(fingerprint);
  }
  
  String _hashUUID(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}

// 2. Certificate Pinning
class HttpClientWithPinning {
  static HttpClient createSecureClient() {
    final client = HttpClient();
    
    client.badCertificateCallback = (cert, host, port) {
      // Implementar certificate pinning
      final trustedCerts = [
        'sha256/YOUR_CERTIFICATE_FINGERPRINT_HERE',
      ];
      
      final certFingerprint = _getCertFingerprint(cert);
      return trustedCerts.contains(certFingerprint);
    };
    
    return client;
  }
  
  static String _getCertFingerprint(X509Certificate cert) {
    // Implementar lógica de fingerprinting
    return '';
  }
}

// 3. Request Interceptor con Token
class AuthInterceptor extends Interceptor {
  final SecureTokenManager tokenManager;
  
  AuthInterceptor(this.tokenManager);
  
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokenManager.getToken();
    
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    handler.next(options);
  }
  
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Token expirado
      tokenManager.deleteToken();
      // Navegar a login/reregistro
    }
    
    handler.next(err);
  }
}

// 4. Encryption at Rest (SQLite local)
class EncryptedLocalDatabase {
  static Future<Database> initDB() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'nodes.db');
    
    // Usar sqflite con encriptación (si es posible)
    // Alternativa: encriptar datos antes de guardar
    
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE nodes (
            uuid TEXT PRIMARY KEY,
            name TEXT,
            color TEXT,
            device_type TEXT,
            metadata_encrypted TEXT,
            created_at INTEGER,
            discovered_at INTEGER
          )
        ''');
      },
    );
  }
  
  static String encryptMetadata(String plaintext, String key) {
    // Usar crypto: flutter_crypto (AES)
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(Key.fromUtf8(key)));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    
    return '${iv.base64}:${encrypted.base64}';
  }
}
7.4 OWASP Top 10 Mitigación
Riesgo OWASPTu AplicaciónMitigaciónA1: InjectionSQL en queriesUsar ORM (Spring Data JPA) + Prepared StatementsA2: Broken AuthUUID sin contraseñaDevice Fingerprinting + JWT + Rate LimitingA3: Sensitive DataUUIDs en cachéEncriptación en reposo + Secure StorageA4: XML/XXENo aplicaNo usas XMLA5: Broken AccessSincronización de datosValidar que UUID del request = tokenA6: Security Misc.DependenciasAuditar con OWASP Dependency CheckA7: XSSNo aplicaNo hay web frontendA8: DeserializationJSON parsingValidar entrada + usar DTOs strictosA9: LoggingAuditoríaLoguear sync, registros, acceso remotoA10: InsufficientDocumentaciónCrear runbook de seguridad

8️⃣ ANÁLISIS DE RIESGOS TÉCNICOS
8.1 Matriz de Riesgos
#RiesgoProbabilidadImpactoSeveridadMitigaciónR1BLE scanning drena bateríaAltaAlto🔴 CríticaDuty cycle + adaptive scanningR2iOS background scan limitado a 10sAltaMedio🟠 AltaEntitlements especiales + reactivaciónR3Escalabilidad: 500+ usuariosMediaAlto🟠 AltaIndexación BD + caché redisR4RSSI inconsistente en obstáculosAltaBajo🟡 MediaMedian filtering + calibrationR5Falsificación de UUIDMediaAlto🟠 AltaDevice fingerprinting + pinningR6Supabase downtimeBajaAlto🟠 AltaQueue local + retry logicR7Colisión de UUIDsMuy BajaCrítica🔴 CríticaUsar UUID v4 estándarR8Memory leak en BLE scanningMediaAlto🟠 AltaTesting en dispositivos realesR9Backward compatibilityMediaMedio🟡 MediaVersionamiento API + migrationsR10Latencia en visualización de grafosMediaMedio🟡 MediaRendering asíncrono + canvas optimizado
8.2 Plan de Mitigación de Riesgos Críticos
R1: Drenaje de Batería (BLE)
yamlProblema:
  - Scanning continuo = 10-15% batería/hora
  - Usuario lo desactiva después de 1 hora
  - App inútil

Solución Multinivel:
  
  Nivel 1: Duty Cycle
    - Scan 2s, pausa 8s
    - Reduce consumo a 1-2% batería/hora
    - Aceptable para usuarios
  
  Nivel 2: Adaptive Mode
    if (batteryLevel < 20%) {
      dutyCycle = 50%  // Scan 2s, pausa 48s
    } else if (batteryLevel < 10%) {
      disableBLEScanning()
      showUserNotification()
    }
  
  Nivel 3: Smart Triggering
    - Solo scan si se detectó cambio en últimos 5min
    - Background geofence (Android) para despertar app
    - iOS motion detection para reactivar
  
  Nivel 4: User Control
    - Slider: "Aggressiveness" (10% a 100%)
    - Mostrar estimación: "Consumo: 3% batería/hora"
    - Presets: Battery Saver, Balanced, Performance

Métricas de Éxito:
  ✅ Consumo < 5% batería/hora en balanced mode
  ✅ User retention > 70% después 7 días
R2: iOS Background Scan (10s límite)
yamlProblema:
  - iOS limita background tasks a 10 segundos
  - No puedes hacer scanning continuo sin foreground
  - Requiere "Privacy - Bluetooth Peripheral Usage"

Solución:

  Opción A: Backgrounding con UIApplication.shared.beginBackgroundTask
    - Solicitar 10 minutos de background (iOS otorga variable)
    - Usar para sync + scan rápido
    - Límite práctico: 5 minutos
    - Problema: Se agota rápido

  Opción B: Location-based Triggering
    - Usar CLLocationManager para "despertar" app
    - Cuando usuario se mueve, activar BLE
    - Problema: Requiere Location permissions
  
  Opción C: Push Notifications (NOT realtime BLE)
    - Backend detecta cambios
    - Envía silent push
    - App se despierta, hace sync
    - Problema: Latencia 1-5 segundos
  
  Opción D: Hybrid (RECOMENDADO) ✅
    - Cuando app está en foreground: scan activo
    - Cuando app en background:
      * Cada 30 segundos: background task
      * Scan por 5 segundos
      * Publiquele nuevos nodos vía notification
    - Usuario puede tener app en home screen (quasi-foreground)

Implementación:
```swift
  // Swift iOS
  func setupBackgroundTask() {
    UIApplication.shared.setMinimumBackgroundFetchInterval(
      UIApplication.backgroundFetchIntervalMinimum // 15 min mínimo
    )
  }
  
  func application(
    _: UIApplication,
    performFetchWithCompletionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Hacer BLE scan por 5 segundos
    // Publicar notificación si hay cambios
    completionHandler(.newData)
  }
```

Métricas:
  ✅ Detectar nuevo nodo en < 2 minutos
  ✅ Sin drenar batería de forma visible
R3: Escalabilidad (500+ usuarios)
yamlProblema:
  - Backend debe soportar:
    * 500 usuarios enviando sync cada 5 minutos
    * Cada sync = request + DB query + cálculos
    * PostgreSQL de Supabase gratuita puede saturarse

Bottlenecks:
  - DB queries lentas
  - Sin índices en columns críticos
  - Sin caché
  - Historial de contactos crece ilimitado

Solución:

  Índices en PostgreSQL:
    CREATE INDEX idx_users_uuid ON users(uuid);
    CREATE INDEX idx_contacts_user_a ON contact_history(user_a_uuid);
    CREATE INDEX idx_contacts_user_b ON contact_history(user_b_uuid);
    CREATE INDEX idx_contacts_created ON contact_history(created_at);
    CREATE INDEX idx_discovery_timestamp ON node_discoveries(discovered_at);
  
  Caché en Backend (Redis):
    - Caché el directorio global de nodes (TTL: 5 minutos)
    - Caché el historial por usuario (TTL: 10 minutos)
    - Caché el estado de sync (TTL: 1 minuto)
    
    @Cacheable(value = "allNodes", unless = "#result == null")
    public List<Node> getAllNodes() { ... }
  
  Paginación en historial:
    GET /api/v1/history/{uuid}?page=0&size=50
    - Limitar a últimos 50 registros por defecto
    - Evitar traer 10000 registros

  Compresión de historial (batch job):
    - Cada noche: agregar contactos > 30 días
    - Tabla: contact_history_archive (compressed)
    - Liberar espacio en tabla caliente

  Escalado horizontal (Render):
    - 100 usuarios: 1x web dyno (512MB)
    - 500 usuarios: 2-3x web dynos + load balancer
    - 1000+ usuarios: Considerar Kubernetes en AWS/GCP

  Database:
    - Supabase free: OK hasta 100-200 users
    - Supabase pro: OK hasta 1000 users
    - Plan: escalada a AWS RDS si > 1000 users

Métricas:
  ✅ p95 latencia sync < 2 segundos
  ✅ Uptime 99.9%
  ✅ Soportar 500 requests/minuto

9️⃣ ROADMAP POR FASES (Detallado)
FASE 0: Investigación y Prototipado (Weeks 1-3)
Objetivos:

Validar viabilidad técnica BLE en Flutter
Proof of concept: comunicación BLE entre 2 dispositivos
Definir stack exacto

Actividades:
yamlWeek 1: Research
  - Lee specs Bluetooth SIG 5.0
  - Estudia flutter_blue_plus codebase
  - Estudia nRF Mesh SDK para Android
  - Contacta Nordic Semiconductor (soporte)
  
Week 2: PoC Mobile
  - Crea proyecto Flutter base
  - Implementa BLE scan simple
  - Implementa BLE advertising simple
  - Test en 2 dispositivos reales (Android + iOS)
  - Mide consumo batería
  
Week 3: PoC Backend
  - Crea proyecto Spring Boot base
  - REST endpoints básicos
  - PostgreSQL schema inicial
  - Deploy en Render
  - Test conectividad desde mobile

Deliverables:
  ✅ PoC Flutter (detectar otros dispositivos)
  ✅ PoC Backend (CRUD de usuarios)
  ✅ Documento de viabilidad BLE
  ✅ Decisión Mesh sí/no
  ✅ Estimación de consumo batería
  
Riesgos:
  ⚠️ BLE en iOS más limitado de lo esperado
  ⚠️ Flutter dependencies desactualizadas
  ⚠️ Supabase API cambios

Tiempo estimado: 3 semanas
Complejidad: ⭐⭐⭐ (investigación + prototipado)

FASE 1: MVP Básico (Weeks 4-10)
Objetivo: Usuario puede iniciar app, detectar otros, sincronizar con backend
yamlBackend (Java Spring Boot):
  
  Semana 4-5: Setup infraestructura
    - Spring Boot v3.x project
    - PostgreSQL schema (users, nodes, history)
    - Docker setup
    - CI/CD básico (GitHub Actions)
    - Deploy en Render
    
    Entidades:
      - User (uuid, name, color, deviceType)
      - Node (uuid, registeredAt, metadata)
      - ContactHistory (userA, userB, timestamp, rssi)
    
    Endpoints:
      POST /api/v1/auth/register
        Input: {uuid, name, color, deviceType, fingerprint}
        Output: {uuid, token, status}
      
      GET /api/v1/users/{uuid}
        Output: {uuid, name, color, deviceType}
      
      GET /api/v1/nodes/directory
        Output: [{ uuid, name, color, deviceType }, ...]
      
      POST /api/v1/sync/{uuid}
        Input: {lastSyncVersion}
        Output: {nodes[], version, timestamp}
      
      POST /api/v1/history/record
        Input: {discoveredBy, nodeUUID, rssi}
        Output: {success}
  
  Semana 6-7: Servicios de dominio
    - UserService: registro, actualización, validación
    - SyncService: construcción de directorio
    - HistoryService: registro de descubrimientos
    - JWT authentication
  
  Semana 8: Testing & Hardening
    - Unit tests (repositories, services)
    - Integration tests (endpoints)
    - Security review (OWASP)
    - Rate limiting
    - Error handling

Mobile (Flutter):
  
  Semana 4-5: Setup & Inicialización
    - Flutter project setup
    - Folder structure (lib/features/...)
    - Dependency injection (GetIt)
    - Secure storage setup
    - Local SQLite database
    
    Features:
      1. app_config (theme, routes)
      2. user (generate UUID, load profile)
      3. ble (scan, advertising)
  
  Semana 6-7: BLE Module
    - flutter_blue_plus integration
    - UUID generation + secure storage
    - BLE scanning logic
    - RSSI → distance conversion
    - Nearby nodes detection
    - Local caching
    
    Lógica de scanning:
      - Duty cycle: scan 2s, pausa 8s
      - RSSI filtering (> -85 dBm)
      - Update UI cada 500ms
      - Historial local
  
  Semana 8-9: Backend Integration
    - Dio HTTP client
    - Auth interceptor + JWT
    - Register endpoint call
    - Sync endpoint call
    - Error handling
    - Offline fallback (caché)
  
  Semana 10: UI Basic
    - Home page (mostrar cercanos)
    - Settings page (nombre, color)
    - Sync button
    - Status indicators
    - Simple visualización (lista)

Deliverables:
  ✅ Backend deployado en Render
  ✅ App Flutter publicable (APK + testflight)
  ✅ Usuario puede:
    - Iniciar app
    - Ver nombre/color
    - Detectar nodos cercanos
    - Sincronizar con backend
    - Ver historial local
  ✅ Documentation básica
  ✅ Performance: < 3% batería/hora

Riesgos:
  ⚠️ Sincronización concurrente (BLE + HTTP)
  ⚠️ Memory leaks en scanning
  ⚠️ UI responsiveness durante scan
  ⚠️ iOS restrictions no anticipadas

Tiempo: 7 semanas
Complejidad: ⭐⭐⭐⭐ (backend + mobile integrados)
Esfuerzo: 2 personas (1 backend + 1 mobile)

FASE 2: Visualización de Grafos (Weeks 11-16)
Objetivo: Cambiar a vista 2D cuando > 4 nodos, mostrar conexiones
yamlBackend:

  Semana 11: Topology API
    - GET /api/v1/mesh/topology/{uuid}
      Input: {depth: 1 | 2}
      Output: {
        "centerNode": {...},
        "nodes": [...],
        "edges": [
          {"from": "uuid1", "to": "uuid2", "lastSeen": timestamp}
        ]
      }
    
    Lógica:
      - depth=1: nodos que A detectó directamente
      - depth=2: nodos que los nodos de A detectaron
      - Máx 100 nodos por petición

Mobile (Flutter):

  Semana 11-12: Graph rendering
    - Integrar graphview / fl_chart
    - Algoritmo force-directed layout (Flutter)
    - Renderizar nodos + edges
    - Animación smooth de posiciones
    
    Librerías recomendadas:
      - graph: para grafo en memoria
      - flutter_svg: para renderizar
      - animations: para smooth transitions
  
  Semana 13: Visualization BLoC
    - VisualizationBloc para lógica de estado
    - Cambio automático simple ↔ grafo
    - Actualización en tiempo real
  
  Semana 14-15: UI Grafo
    - GrafoPage (vista principal)
    - NodeCard (mostrar info)
    - EdgeWidget (líneas con animación)
    - Zoom + pan gesture
    - Tooltip con información
  
  Semana 16: Optimización
    - Caché de layouts
    - Rendering asíncrono
    - Performance testing
    - Batería impact

Deliverables:
  ✅ Visualización dinámica (simple ↔ grafo)
  ✅ Mostrar topología hasta 100 nodos
  ✅ Smooth animations
  ✅ Zoom/pan funcional
  ✅ Performance: 60 FPS en grafo simple

Riesgos:
  ⚠️ Rendering performance con 100+ nodos
  ⚠️ Layout algoritmo inestable
  ⚠️ Memory usage en grafo grande

Tiempo: 6 semanas
Complejidad: ⭐⭐⭐⭐⭐ (algoritmos + renderizado)

FASE 3: Historial Local Avanzado (Weeks 17-20)
Objetivo: Guardar datos de contacto, mostrar estadísticas
yamlBackend:

  Semana 17: Analytics Endpoints
    GET /api/v1/history/stats/{uuid}
      - Total contactos
      - Contactos únicos
      - Duración promedio
      - Nodos más frecuentes
    
    GET /api/v1/history/timeline/{uuid}?days=7
      - Grafo de timeline

Mobile:

  Semana 18: Historial UI
    - HistoryPage mostrando contactos pasados
    - Filtros por fecha/nombre
    - Timeline view
    - Estadísticas de contacto
  
  Semana 19-20: Sincronización del historial
    - Upload historial local al backend
    - Merge con datos remotos
    - Visualizar datos históricos

Deliverables:
  ✅ Historial local sin límite (SQLite)
  ✅ UI para explorar historial
  ✅ Estadísticas de contacto
  ✅ Sincronización bidireccional

Tiempo: 4 semanas
Complejidad: ⭐⭐⭐

FASE 4: Vista Administrador (Weeks 21-24)
Objetivo: Expandir topología más allá de contactos directos
yamlBackend:

  Semana 21: Mesh query service
    - BFS/DFS algoritmo para topología
    - Cache de topología (TTL 5min)
    - Limitación: max 500 nodos

Mobile:

  Semana 22-23: Admin View UI
    - Visualizar árbol jerárquico
    - "Yo" como raíz
    - Profundidad 2-3
    - Indicar información compartida (gossip)
  
  Semana 24: Sync de información compartida
    - Cuando conecta a nodo B, obtener sus contactos
    - Mostrar estructura expandida

Deliverables:
  ✅ Admin view funcional
  ✅ Topología expandida hasta depth=3
  ✅ Sincronización local de información

Tiempo: 4 semanas
Complejidad: ⭐⭐⭐⭐

FASE 5: Sincronización Avanzada (Weeks 25-30)
Objetivo: Gossip protocol, compartir información entre dispositivos
yamlBackend:

  Semana 25-26: Gossip API
    POST /api/v1/gossip/share/{uuid}
      Input: {contactos que B conoce}
      Output: {nueva info para B}
  
  Semana 27: Conflict resolution
    - ¿Qué hacer si hay conflictos de info?
    - Last-write-wins strategy
    - Timestamp-based merging

Mobile:

  Semana 28-30: Local gossip protocol
    - Cuando conecta a nodo B vía GATT
    - Enviar: "Estos son los nodos que detecté"
    - Recibir: "Aquí están los que detecté yo"
    - Merge local

Deliverables:
  ✅ Gossip protocol local funcionando
  ✅ Sincronización automática de topología
  ✅ Expandir red hasta 50 nodos sin internet

Tiempo: 6 semanas
Complejidad: ⭐⭐⭐⭐⭐

FASE 6: Bluetooth Mesh (Weeks 31-50)
Nota: Esta es la fase más compleja. Requiere decisión previa sobre viabilidad.
yamlOpción A: Investigación & Prototipo SOLO

  Semana 31-40: Research nRF Mesh SDK
    - Estudiar Nordic Semiconductor docs
    - Crear prototipo Android
    - Test en hardware real (nRF devices)
    - Evaluar viabilidad iOS
  
  Semana 41-50: Decision & roadmap futuro
    - ¿Es viable para el proyecto?
    - ¿Costo/beneficio justo?
    - Plan de implementación para año 2

Opción B: Implementación completa

  **Desaconsejado en FASE 6**
  - Requiere 6+ meses
  - Riesgo técnico muy alto
  - Mejor hacerlo cuando MVP esté estable

Deliverables (Opción A):
  ✅ Prototipo Mesh en Android
  ✅ Documento de viabilidad iOS
  ✅ Roadmap Mesh 2-3 años

Tiempo: 20 semanas (solo investigación)
Complejidad: ⭐⭐⭐⭐⭐⭐

FASE 7: Escalabilidad & Producción (Weeks 51-60)
yamlInfraestructura:

  Semana 51-52: Load testing
    - Simular 500 usuarios
    - Medir performance
    - Identificar bottlenecks
    - Escalar si es necesario
  
  Semana 53: Security audit
    - Penetration testing
    - OWASP review
    - Bug bounty (opcional)
  
  Semana 54: Monitoring
    - Setup Sentry (error tracking)
    - Setup DataDog (APM)
    - Alertas en Render
  
  Semana 55-56: App store publishing
    - Google Play Store
    - Apple App Store
    - Proceso de review (2-4 semanas)
  
  Semana 57-60: Marketing & launch
    - Beta testing program
    - Community feedback
    - Launch event
    - Post-launch support

Deliverables:
  ✅ App en ambos stores
  ✅ 1000+ descargas
  ✅ 99.9% uptime
  ✅ Monitored 24/7

Tiempo: 10 semanas
Complejidad: ⭐⭐⭐⭐

🔟 ESCALABILIDAD Y LIMITACIONES REALES
10.1 Análisis por Rango de Usuarios
┌─────────────┬───────────────────┬──────────────┬──────────────────┐
│ Usuarios    │ Infraestructura    │ Limitaciones │ Soluciones       │
├─────────────┼───────────────────┼──────────────┼──────────────────┤
│ 20 usuarios │ Render: free tier  │ Ninguna      │ MVP               │
│             │ Supabase: free     │              │ Funcional         │
│             │ 1 dyno             │              │                   │
│             │                    │              │                   │
│ 50 usuarios │ Render: hobbyist   │ BLE:         │ Duty cycle       │
│             │ Supabase: free     │ Rango 50m    │ Algoritmo OK     │
│             │ 1 dyno             │ (evento)     │                   │
│             │                    │              │                   │
│ 100 usuarios│ Render: standard   │ BLE: latencia│ Índices en DB    │
│             │ Supabase: pro      │ 100-500ms    │ Caché (Redis)    │
│             │ 1 dyno             │              │ Escalamiento     │
│             │                    │              │ Prototipo Mesh   │
│             │                    │              │                   │
│ 500 usuarios│ Render: 2-3 dynos  │ BLE: hasta 6 │ Sharding histórico
│             │ Supabase: pro      │ hops en Mesh │ Compresión datos │
│             │ + pgBouncer        │ Latencia 1s+ │ Load balancing   │
│             │ Scaling: ~$150/mo  │              │ API rate limit   │
│             │                    │              │                   │
│ 1000 users  │ AWS RDS + Replica  │ BLE: requiere│ Read replicas    │
│             │ Kubernetes (k8s)   │ Mesh activo  │ Kubernetes       │
│             │ Load balancer      │ Topología    │ Redis cluster    │
│             │ CloudFront CDN     │ 100+ hops    │ Mesh obligatorio │
│             │ Scaling: ~$500/mo  │              │ Celular arch     │
│             │                    │              │                   │
│ 5000+ users │ Multi-region       │ BLE limitado │ Considerar otra  │
│             │ deployment         │ para Mesh    │ tecnología:      │
│             │ Geo-replication    │ Solo local   │ LoRa, NB-IoT    │
│             │ Scaling: $2000+/mo │ sync         │                  │
└─────────────┴───────────────────┴──────────────┴──────────────────┘
10.2 Estimación de Costos
yamlFASE 1 (MVP, 20-50 usuarios):

  Infraestructura:
    - Render (Hobby tier): FREE (0 USD)
    - Supabase (Free): FREE (0 USD)
    - GitHub Actions: FREE (0 USD)
    
  Desarrollo:
    - 1 backend dev (10 semanas × 40h): ~$10K
    - 1 mobile dev (10 semanas × 40h): ~$10K
    - QA/Testing: ~$3K
    
  Total FASE 1: ~$23K

FASE 2-4 (Visualización + Historial, 50-200 usuarios):

  Infraestructura:
    - Render (Standard): ~$12/mes → ~$150/año
    - Supabase (Pro): ~$25/mes → ~$300/año
    - Monitoring (Sentry): ~$20/mes → ~$240/año
    - CDN (Cloudflare): ~$5/mes → ~$60/año
    
  Desarrollo:
    - Backend (6 semanas): ~$6K
    - Mobile (6 semanas): ~$6K
    - QA: ~$2K
    
  Total FASES 2-4: ~$614K + $16.2K dev = ~$32K/año

FASE 5-6 (Escalabilidad, 200-1000+ usuarios):

  Infraestructura:
    - AWS RDS (db.t3.medium): ~$50/mes → ~$600/año
    - Render (2-3x Standard): ~$36/mes → ~$432/año
    - Redis cluster: ~$30/mes → ~$360/año
    - Monitoring: ~$50/mes → ~$600/año
    
  Desarrollo:
    - Backend (8 semanas): ~$8K
    - Mobile (8 semanas): ~$8K
    - DevOps (4 weeks): ~$4K
    - QA: ~$3K
    
  Total FASES 5-6: ~$2.4K infra + $23K dev = ~$25.4K/año

TOTAL ESTIMADO (3 años):
  - Year 1: ~$40K (desarrollo + infra)
  - Year 2: ~$32K
  - Year 3: ~$30K
  ─────────────
  Total: ~$102K
10.3 Límites Técnicos Realistas
BLE Limitations:

  ✅ Alcanzable (Fase 1-5):
    - 20-500 usuarios
    - Topología hasta depth 3
    - Latencia < 5 segundos
    - Alcance: evento/universidad (100m)
  
  ⚠️ Muy desafiante (Fase 6):
    - Mesh activo en ambas plataformas
    - Alcance > 500 metros
    - 1000+ nodos simultáneos
    - Baja latencia en topología completa
  
  ❌ NO viable con BLE:
    - 10000+ usuarios en mesh
    - Alcance > 1000 metros
    - Comunicación en tiempo real
    - Garantías de entrega 100%

Alternativas para escalar > 1000 usuarios:

  1. LoRa (WAN de largo alcance)
     - Alcance: 10+ km
     - Bandwidth: bajo (240 bps)
     - Costo: $100-500 por dispositivo
  
  2. NB-IoT (celular IoT)
     - Operador: Movistar, Personal, etc.
     - Costo: $10-30/mes por SIM
     - Alcance: nacional
  
  3. Combinado: BLE + LoRa
     - BLE local (proximidad)
     - LoRa para relaying
     - Híbrido mejor

📊 RESUMEN EJECUTIVO
¿Cómo proceder?
RECOMENDACIÓN FINAL:

1. **Tecnología:** Flutter + Java Spring Boot ✅
   - BLE en Flutter es superior
   - Backend agnóstico (escalable)

2. **Arquitectura:** Hexagonal + DDD ✅
   - Limpia, testeable, mantenible
   - Preparada para crecer

3. **Seguridad:** Multi-capa sin contraseña ✅
   - UUID + Device Fingerprinting
   - JWT + Certificate Pinning
   - Encriptación en reposo

4. **Roadmap:** 60 semanas (12-15 meses) ✅
   - Fase 1 (MVP): 7 semanas
   - Fases 2-7 (Escalabilidad): 53 semanas

5. **Inversión:** ~$100K (todo incluido) ✅
   - Equipo: 2-3 developers
   - Infraestructura: mínima al inicio

6. **Potencial:** ALTO ✅
   - Eventos (conciertos, conferencias)
   - Universidades (networking)
   - Comunidades (redes locales)