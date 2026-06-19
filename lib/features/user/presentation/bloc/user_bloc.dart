import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/user/domain/entities/user.dart';
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
/// No persiste en DB — solo en memoria (deferido a Phase 3).
class UpdateThemeMode extends UserEvent {
  final ThemeMode mode;

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
  /// Modo de tema actual. Por defecto [ThemeMode.system] (deferido al SO).
  final ThemeMode themeMode;

  const UserLoaded(this.user, {this.themeMode = ThemeMode.system});

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

  UserBloc({
    required this.getProfile,
    required this.updateName,
    required this.updateColor,
  }) : super(const UserInitial()) {
    on<LoadProfile>(_onLoadProfile);
    on<UpdateUserNameEvent>(_onUpdateName);
    on<UpdateUserColorEvent>(_onUpdateColor);
    on<UpdateThemeMode>(_onUpdateThemeMode);
  }

  Future<void> _onLoadProfile(
      LoadProfile event, Emitter<UserState> emit) async {
    emit(const UserLoading());
    final result = await getProfile(const NoParams());
    result.fold(
      (failure) => emit(UserError(failure.message)),
      (user) => emit(UserLoaded(user)),
    );
  }

  Future<void> _onUpdateName(
      UpdateUserNameEvent event, Emitter<UserState> emit) async {
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
      (user) => emit(UserLoaded(user)),
    );
  }

  Future<void> _onUpdateColor(
      UpdateUserColorEvent event, Emitter<UserState> emit) async {
    emit(const UserLoading());
    final result = await updateColor(UpdateUserColorParams(color: event.color));
    if (result.isLeft()) {
      emit(UserError(result.fold((l) => l.message, (_) => '')));
      return;
    }
    final profileResult = await getProfile(const NoParams());
    profileResult.fold(
      (failure) => emit(UserError(failure.message)),
      (user) => emit(UserLoaded(user)),
    );
  }

  /// Actualiza el modo de tema sin modificar datos del perfil.
  ///
  /// Solo cambia el campo [themeMode] en el estado actual.
  /// No persiste en DB (deferido a Phase 3).
  /// Si el estado actual no es [UserLoaded], ignora el evento.
  void _onUpdateThemeMode(
      UpdateThemeMode event, Emitter<UserState> emit) {
    final currentState = state;
    if (currentState is UserLoaded) {
      emit(UserLoaded(currentState.user, themeMode: event.mode));
    }
  }
}
