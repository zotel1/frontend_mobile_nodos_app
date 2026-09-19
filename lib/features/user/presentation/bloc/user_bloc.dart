import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/core/errors/failures.dart';
import 'package:frontend_mobile_nodos_app/core/utils/app_theme_mode.dart';
import 'package:frontend_mobile_nodos_app/core/utils/uuid_generator.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/repositories/user_repository.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/get_user_profile.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_color.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/usecases/update_user_name.dart';
import 'package:frontend_mobile_nodos_app/core/usecases/usecase.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/ensure_local_node.dart';

// ── Events ──

abstract class UserEvent extends Equatable {
  const UserEvent();

  @override
  List<Object?> get props => [];
}

class LoadProfile extends UserEvent {
  const LoadProfile();
}

class UpdateUserNameEvent extends UserEvent {
  final String name;

  const UpdateUserNameEvent(this.name);

  @override
  List<Object> get props => [name];
}

class UpdateUserColorEvent extends UserEvent {
  final String color;

  const UpdateUserColorEvent(this.color);

  @override
  List<Object> get props => [color];
}

/// Crea o asegura el perfil del usuario con los valores del onboarding.
///
/// QUÉ: se despacha desde OnboardingPage._saveAndStart() ANTES de los updates.
/// Si el perfil ya existe (ej. LoadProfile de app.dart creó uno default),
/// actualiza nombre y color en lugar de fallar.
///
/// POR QUÉ: sin este evento, UpdateUserNameEvent y UpdateUserColorEvent
/// fallaban silenciosamente en primera ejecución porque la tabla users
/// estaba vacía y los handlers esperaban una fila existente.
class CreateUserProfile extends UserEvent {
  final String name;
  final String color;

  const CreateUserProfile(this.name, this.color);

  @override
  List<Object> get props => [name, color];
}

/// Cambia el modo de tema (sistema / claro / oscuro).
///
/// Persiste en SharedPreferences bajo la clave 'theme_mode'
/// para que sobreviva a reinicios de la app.
class UpdateThemeMode extends UserEvent {
  final AppThemeMode mode;

  const UpdateThemeMode(this.mode);

  @override
  List<Object> get props => [mode];
}

// ── States ──

abstract class UserState extends Equatable {
  const UserState();

  @override
  List<Object?> get props => [];
}

class UserInitial extends UserState {
  const UserInitial();
}

class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  final User user;

  /// Modo de tema actual. Por defecto [AppThemeMode.system] (deferido al SO).
  final AppThemeMode themeMode;

  const UserLoaded(this.user, {this.themeMode = AppThemeMode.system});

  @override
  List<Object?> get props => [user, themeMode];
}

class UserError extends UserState {
  final String message;

  const UserError(this.message);

  @override
  List<Object> get props => [message];
}

// ── BLoC ──

class UserBloc extends Bloc<UserEvent, UserState> {
  final GetUserProfile getProfile;
  final UpdateUserName updateName;
  final UpdateUserColor updateColor;

  /// Garantiza que cada User cargado tenga un Node persistente real
  /// que represente al dispositivo local dentro del grafo.
  ///
  /// ARCH-001: UserLoaded solo debe emitirse después de asegurar
  /// User.localNodeId → Nodes.id.
  final EnsureLocalNode ensureLocalNode;

  /// Repositorio inyectado para auto-crear el perfil default
  /// cuando la DB está vacía (primera ejecución).
  /// QUÉ: usado por _onLoadProfile para persistir el User default
  /// en caso de que getUser() retorne null.
  final UserRepository _userRepository;

  /// SharedPreferences para persistir preferencias como el tema.
  /// QUÉ: usado por _onLoadProfile para leer el tema guardado y
  /// por _onUpdateThemeMode para persistir el cambio.
  final SharedPreferences _prefs;

  UserBloc({
    required this.getProfile,
    required this.updateName,
    required this.updateColor,
    required this.ensureLocalNode,
    required UserRepository userRepository,
    required SharedPreferences prefs,
  }) : _userRepository = userRepository,
       _prefs = prefs,
       super(const UserInitial()) {
    on<LoadProfile>(_onLoadProfile);
    on<CreateUserProfile>(_onCreateProfile);
    on<UpdateUserNameEvent>(_onUpdateName);
    on<UpdateUserColorEvent>(_onUpdateColor);
    on<UpdateThemeMode>(_onUpdateThemeMode);
  }

  /// Expone el UUID persistente del dispositivo del usuario (myDeviceUuid).
  ///
  /// QUÉ: lee el UUID desde SharedPreferences bajo la clave 'device_uuid'.
  /// Retorna null si el perfil no fue creado aún o si la clave no existe.
  ///
  /// POR QUÉ: otros componentes (visualization, nodes) necesitan el UUID
  /// del dispositivo propio para marcar el self-node en el grafo y para
  /// filtrar el dispositivo propio de la lista de nodos detectados.
  /// Sin este getter, el UUID queda encapsulado en _createDefaultProfile
  /// y es inaccesible desde fuera del BLoC.
  ///
  /// El UUID se genera UNA SOLA VEZ por instalación y se persiste en
  /// SharedPreferences, por lo que sobrevive a reinicios de la app
  /// y a recreaciones del perfil.
  String? get myDeviceUuid => _prefs.getString('device_uuid');

  /// Carga el perfil del usuario desde Drift.
  ///
  /// F7: Si no existe perfil (primera ejecución), crea un User default
  /// con UUIDv4, nombre "Mi dispositivo", color azul (#2196F3), y
  /// deviceType "android". Luego recarga el perfil para obtener los
  /// datos persistidos.
  ///
  /// PR4: El UUID se genera UNA SOLA VEZ por instalación y se persiste
  /// en SharedPreferences bajo 'device_uuid'. Si el perfil se recrea
  /// (por corrupción o reseteo), se reusa el mismo UUID.
  ///
  /// PR4: Solo crea perfil default cuando el fallo es
  /// CacheFailure('No user profile found'). DatabaseFailure y
  /// UnexpectedFailure emiten UserError en vez de crear perfil fantasma.
  ///
  /// Tema: lee el tema guardado en SharedPreferences bajo la clave
  /// 'theme_mode'. Si no existe, usa [AppThemeMode.system] por defecto.
  ///
  /// QUÉ problema resuelve: sin este fallback, Settings mostraba
  /// "Error: No user profile found" en primera ejecución porque
  /// la DB de usuarios estaba vacía.
  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<UserState> emit,
  ) async {
    final AppThemeMode currentThemeMode;

    if (state is UserLoaded) {
      currentThemeMode = (state as UserLoaded).themeMode;
    } else {
      currentThemeMode = _themeModeFromPrefs();
    }

    emit(const UserLoading());

    final result = await getProfile(const NoParams());

    if (result.isLeft()) {
      final failure = result.fold(
        (left) => left,
        (_) => throw StateError('Resultado inconsistente en GetUserProfile.'),
      );

      if (failure is CacheFailure &&
          failure.message == 'No user profile found') {
        await _createDefaultProfile(emit, currentThemeMode);
        return;
      }

      emit(UserError(failure.message));
      return;
    }

    final user = result.getOrElse(
      () => throw StateError('Se esperaba un User válido.'),
    );

    await _emitLoadedWithLocalNode(user, currentThemeMode, emit);
  }

  /// Crea un perfil default con UUID persistente.
  ///
  /// PR4: El UUID se lee de SharedPreferences (clave 'device_uuid').
  /// Si no existe, se genera uno nuevo con [generateUuidV4] y se
  /// persiste. Esto garantiza que el dispositivo mantenga la misma
  /// identidad incluso si la tabla users se corrompe y se recrea.
  ///
  /// Después de crear el perfil, recarga desde la DB para obtener
  /// los datos con el id asignado por Drift.
  Future<void> _createDefaultProfile(
    Emitter<UserState> emit,
    AppThemeMode themeMode,
  ) async {
    var uuid = _prefs.getString('device_uuid');

    if (uuid == null || uuid.isEmpty) {
      uuid = generateUuidV4();

      await _prefs.setString('device_uuid', uuid);
    }

    final defaultUser = User(
      uuid: uuid,
      name: 'Mi dispositivo',
      color: '#2196F3',
      deviceType: 'android',
      createdAt: DateTime.now(),
    );

    await _userRepository.createUser(defaultUser);

    final persistedUser = await _userRepository.getUserProfile();

    if (persistedUser == null) {
      emit(const UserError('No se pudo recuperar el perfil recién creado.'));
      return;
    }

    await _emitLoadedWithLocalNode(persistedUser, themeMode, emit);
  }

  /// Crea o asegura el perfil del usuario con los valores del onboarding.
  ///
  /// QUÉ: se llama desde OnboardingPage._saveAndStart(). Intenta crear
  /// un User con los datos del onboarding. Si el perfil ya existe
  /// (LoadProfile de app.dart lo creó con defaults), actualiza nombre
  /// y color para no perder los valores del usuario.
  ///
  /// POR QUÉ: en primera ejecución, LoadProfile crea un perfil default
  /// ("Mi dispositivo", #2196F3). Este handler sobrescribe esos valores
  /// con los que el usuario eligió en el onboarding, o crea el perfil
  /// desde cero si LoadProfile aún no terminó.
  ///
  /// Después de crear/actualizar, recarga el perfil completo desde
  /// la DB para emitir UserLoaded con los datos persistidos.
  Future<void> _onCreateProfile(
    CreateUserProfile event,
    Emitter<UserState> emit,
  ) async {
    final currentThemeMode = state is UserLoaded
        ? (state as UserLoaded).themeMode
        : AppThemeMode.system;

    emit(const UserLoading());

    try {
      var uuid = _prefs.getString('device_uuid');

      if (uuid == null || uuid.isEmpty) {
        uuid = generateUuidV4();

        await _prefs.setString('device_uuid', uuid);
      }

      final existing = await _userRepository.getUserProfile();

      if (existing != null) {
        await _userRepository.updateName(event.name);

        await _userRepository.updateColor(event.color);
      } else {
        final user = User(
          uuid: uuid,
          name: event.name,
          color: event.color,
          deviceType: 'android',
          createdAt: DateTime.now(),
        );

        await _userRepository.createUser(user);
      }

      final persistedUser = await _userRepository.getUserProfile();

      if (persistedUser == null) {
        emit(
          const UserError('No se pudo recuperar el perfil después de crearlo.'),
        );
        return;
      }

      await _emitLoadedWithLocalNode(persistedUser, currentThemeMode, emit);
    } catch (e) {
      emit(UserError('Error al crear perfil: $e'));
    }
  }

  /// Emite UserLoaded únicamente después de garantizar que el perfil
  /// tenga asociado un self-node persistente real.
  ///
  /// ARCH-001:
  ///
  /// 1. EnsureLocalNode crea o recupera el Node local.
  /// 2. Persiste User.localNodeId.
  /// 3. Recarga User desde Drift.
  /// 4. Recién entonces emite UserLoaded.
  ///
  /// De esta manera ningún consumidor de UserLoaded necesita conocer
  /// cómo se crea el nodo local ni preocuparse por estados intermedios.
  Future<void> _emitLoadedWithLocalNode(
  User user,
  AppThemeMode themeMode,
  Emitter<UserState> emit,
) async {
  final ensureResult = await ensureLocalNode(user);

  if (ensureResult.isLeft()) {
    final message = ensureResult.fold(
      (failure) => failure.message,
      (_) => 'Error desconocido al crear el nodo local.',
    );

    emit(
      UserError(
        'No se pudo inicializar la identidad local: $message',
      ),
    );
    return;
  }

  final localNode = ensureResult.getOrElse(
    () => throw StateError(
      'EnsureLocalNode retornó un resultado inconsistente.',
    ),
  );

  if (localNode.id == null) {
    emit(
      const UserError(
        'El nodo local no tiene un ID persistente.',
      ),
    );
    return;
  }

  // EnsureLocalNode ya persistió Users.localNodeId.
  // Para el estado en memoria podemos reflejar inmediatamente
  // esa asociación sin una consulta extra.
  final loadedUser = user.copyWith(
    localNodeId: localNode.id,
  );

  emit(
    UserLoaded(
      loadedUser,
      themeMode: themeMode,
    ),
  );
}
  /// Lee el modo de tema desde SharedPreferences.
  ///
  /// QUÉ: convierte el string guardado bajo 'theme_mode' en un
  /// [AppThemeMode]. Si la clave no existe o el valor es inválido,
  /// retorna [AppThemeMode.system].
  ///
  /// PR5a: usa [AppThemeMode.fromString] para centralizar el parseo.
  AppThemeMode _themeModeFromPrefs() {
    final modeStr = _prefs.getString('theme_mode') ?? '';
    return AppThemeMode.fromString(modeStr);
  }

  Future<void> _onUpdateName(
    UpdateUserNameEvent event,
    Emitter<UserState> emit,
  ) async {
    final currentThemeMode = state is UserLoaded
        ? (state as UserLoaded).themeMode
        : AppThemeMode.system;

    emit(const UserLoading());

    final result = await updateName(UpdateUserNameParams(name: event.name));

    if (result.isLeft()) {
      emit(UserError(result.fold((failure) => failure.message, (_) => '')));
      return;
    }

    final persistedUser = await _userRepository.getUserProfile();

    if (persistedUser == null) {
      emit(
        const UserError(
          'No se pudo recuperar el perfil después de actualizar el nombre.',
        ),
      );
      return;
    }

    await _emitLoadedWithLocalNode(persistedUser, currentThemeMode, emit);
  }

  Future<void> _onUpdateColor(
    UpdateUserColorEvent event,
    Emitter<UserState> emit,
  ) async {
    final currentThemeMode = state is UserLoaded
        ? (state as UserLoaded).themeMode
        : AppThemeMode.system;

    emit(const UserLoading());

    final result = await updateColor(UpdateUserColorParams(color: event.color));

    if (result.isLeft()) {
      emit(UserError(result.fold((failure) => failure.message, (_) => '')));
      return;
    }

    final persistedUser = await _userRepository.getUserProfile();

    if (persistedUser == null) {
      emit(
        const UserError(
          'No se pudo recuperar el perfil después de actualizar el color.',
        ),
      );
      return;
    }

    await _emitLoadedWithLocalNode(persistedUser, currentThemeMode, emit);
  }

  /// Actualiza el modo de tema y lo persiste en SharedPreferences.
  ///
  /// Guarda el valor como string ('system', 'light', 'dark') bajo la
  /// clave 'theme_mode' para que sobreviva a reinicios de la app.
  /// Si el estado actual no es [UserLoaded], ignora el evento.
  void _onUpdateThemeMode(UpdateThemeMode event, Emitter<UserState> emit) {
    final currentState = state;
    if (currentState is UserLoaded) {
      _prefs.setString('theme_mode', event.mode.name);
      emit(UserLoaded(currentState.user, themeMode: event.mode));
    }
  }
}
