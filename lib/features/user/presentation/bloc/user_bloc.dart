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
  ///
  /// PR5a: usa [AppThemeMode] en lugar de [ThemeMode] de Flutter.
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
    required UserRepository userRepository,
    required SharedPreferences prefs,
  }) : _userRepository = userRepository,
       _prefs = prefs,
       super(const UserInitial()) {
    on<LoadProfile>(_onLoadProfile);
    on<UpdateUserNameEvent>(_onUpdateName);
    on<UpdateUserColorEvent>(_onUpdateColor);
    on<UpdateThemeMode>(_onUpdateThemeMode);
  }

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
  /// 'theme_mode'. Si no existe, usa [ThemeMode.system] por defecto.
  ///
  /// QUÉ problema resuelve: sin este fallback, Settings mostraba
  /// "Error: No user profile found" en primera ejecución porque
  /// la DB de usuarios estaba vacía.
  Future<void> _onLoadProfile(
      LoadProfile event, Emitter<UserState> emit) async {
    // PR4: Capturar themeMode. Si hay estado previo UserLoaded, preservarlo.
    // Si es UserInitial (primera carga), leer de SharedPreferences.
    // Si no hay valor guardado, usar AppThemeMode.system.
    final AppThemeMode currentThemeMode;
    if (state is UserLoaded) {
      currentThemeMode = (state as UserLoaded).themeMode;
    } else {
      currentThemeMode = _themeModeFromPrefs();
    }

    emit(const UserLoading());

    final result = await getProfile(const NoParams());

    // PR4: Usar result.fold() para diferenciar tipos de Failure.
    // Solo CacheFailure('No user profile found') dispara la creación
    // automática de perfil default.
    return result.fold(
      (failure) async {
        // PR4: Solo crear perfil default si es "no encontrado".
        // DatabaseFailure y UnexpectedFailure → UserError.
        if (failure is CacheFailure &&
            failure.message == 'No user profile found') {
          await _createDefaultProfile(emit, currentThemeMode);
        } else {
          emit(UserError(failure.message));
        }
      },
      (user) => emit(UserLoaded(user, themeMode: currentThemeMode)),
    );
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
    // PR4: Reusar UUID persistido o generar uno nuevo.
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

    // Recargar perfil para obtener los datos persistidos.
    final reloadResult = await getProfile(const NoParams());
    reloadResult.fold(
      (failure) => emit(UserError(failure.message)),
      (user) => emit(UserLoaded(user, themeMode: themeMode)),
    );
  }

  /// Lee el modo de tema desde SharedPreferences.
  ///
  /// QUÉ: convierte el string guardado bajo 'theme_mode' en un
  /// [AppThemeMode]. Si la clave no existe o el valor es inválido,
  /// retorna [AppThemeMode.system].
  ///
  /// PR5a: usa [AppThemeMode.fromString] en lugar de un switch manual.
  /// POR QUÉ: centraliza la lógica de parseo para que _onLoadProfile
  /// y cualquier otro handler puedan leer el tema persistido sin
  /// repetir el switch.
  AppThemeMode _themeModeFromPrefs() {
    final modeStr = _prefs.getString('theme_mode') ?? '';
    return AppThemeMode.fromString(modeStr);
  }

  Future<void> _onUpdateName(
      UpdateUserNameEvent event, Emitter<UserState> emit) async {
    // T-PR1-004: Capturar themeMode actual ANTES de emitir UserLoading.
    // QUÉ problema resuelve: antes _onUpdateName emitía UserLoaded(user)
    // sin el parámetro themeMode, lo que reseteaba el tema a system.
    // Si el usuario estaba en modo oscuro y cambiaba su nombre, el tema
    // volvía a system. Ahora preserva el themeMode del estado anterior.
    final currentThemeMode = state is UserLoaded
        ? (state as UserLoaded).themeMode
        : AppThemeMode.system;

    emit(const UserLoading());
    final result = await updateName(UpdateUserNameParams(name: event.name));
    if (result.isLeft()) {
      emit(UserError(result.fold((l) => l.message, (_) => '')));
      return;
    }
    // Reload profile to get updated user data.
    final profileResult = await getProfile(const NoParams());
    profileResult.fold(
      (failure) => emit(UserError(failure.message)),
      (user) => emit(UserLoaded(user, themeMode: currentThemeMode)),
    );
  }

  Future<void> _onUpdateColor(
      UpdateUserColorEvent event, Emitter<UserState> emit) async {
    // T-PR1-004: Capturar themeMode actual antes de emitir UserLoading.
    // Mismo bug que _onUpdateName — el tema se reseteaba a system al
    // cambiar el color, perdiendo la preferencia del usuario.
    final currentThemeMode = state is UserLoaded
        ? (state as UserLoaded).themeMode
        : AppThemeMode.system;

    emit(const UserLoading());
    final result = await updateColor(UpdateUserColorParams(color: event.color));
    if (result.isLeft()) {
      emit(UserError(result.fold((l) => l.message, (_) => '')));
      return;
    }
    final profileResult = await getProfile(const NoParams());
    profileResult.fold(
      (failure) => emit(UserError(failure.message)),
      (user) => emit(UserLoaded(user, themeMode: currentThemeMode)),
    );
  }

  /// Actualiza el modo de tema y lo persiste en SharedPreferences.
  ///
  /// Guarda el valor como string ('system', 'light', 'dark') bajo la
  /// clave 'theme_mode' para que sobreviva a reinicios de la app.
  /// Si el estado actual no es [UserLoaded], ignora el evento.
  void _onUpdateThemeMode(
      UpdateThemeMode event, Emitter<UserState> emit) {
    final currentState = state;
    if (currentState is UserLoaded) {
      _prefs.setString('theme_mode', event.mode.name);
      emit(UserLoaded(currentState.user, themeMode: event.mode));
    }
  }
}
