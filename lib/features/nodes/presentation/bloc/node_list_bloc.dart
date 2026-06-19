import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/entities/node.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/observe_nodes.dart';
import 'package:frontend_mobile_nodos_app/features/nodes/domain/usecases/update_node_metadata.dart';

// ── Events ──

abstract class NodeListEvent extends Equatable {
  const NodeListEvent();

  @override
  List<Object?> get props => [];
}

class LoadNodes extends NodeListEvent {
  const LoadNodes();
}

class NodeDetected extends NodeListEvent {
  final Node node;

  const NodeDetected(this.node);

  @override
  List<Object> get props => [node];
}

class RefreshNodes extends NodeListEvent {
  const RefreshNodes();
}

// ── States ──

abstract class NodeListState extends Equatable {
  const NodeListState();

  @override
  List<Object?> get props => [];
}

class NodeListInitial extends NodeListState {
  const NodeListInitial();
}

class NodeListLoading extends NodeListState {
  const NodeListLoading();
}

class NodeListLoaded extends NodeListState {
  final List<Node> nodes;

  const NodeListLoaded(this.nodes);

  @override
  List<Object> get props => [nodes];
}

class NodeListEmpty extends NodeListState {
  const NodeListEmpty();
}

class NodeListError extends NodeListState {
  final String message;

  const NodeListError(this.message);

  @override
  List<Object> get props => [message];
}

// ── BLoC ──

class NodeListBloc extends Bloc<NodeListEvent, NodeListState> {
  final ObserveNodes observeNodes;
  final UpdateNodeMetadata updateNodeMetadata;
  StreamSubscription<List<Node>>? _nodesSubscription;

  NodeListBloc({
    required this.observeNodes,
    required this.updateNodeMetadata,
  }) : super(const NodeListInitial()) {
    on<LoadNodes>(_onLoadNodes);
    on<NodeDetected>(_onNodeDetected);
    on<RefreshNodes>(_onRefreshNodes);
    on<_NodesUpdated>(_onNodesUpdated);
    on<_NodesUpdatedEmpty>(_onNodesUpdatedEmpty);
    on<_NodesLoadError>(_onNodesLoadError);
  }

  Future<void> _onLoadNodes(
      LoadNodes event, Emitter<NodeListState> emit) async {
    await _subscribeToNodes(emit);
  }

  void _onNodeDetected(
      NodeDetected event, Emitter<NodeListState> emit) {
    emit(NodeListLoaded([event.node]));
  }

  Future<void> _onRefreshNodes(
      RefreshNodes event, Emitter<NodeListState> emit) async {
    await _subscribeToNodes(emit);
  }

  Future<void> _subscribeToNodes(Emitter<NodeListState> emit) async {
    emit(const NodeListLoading());
    await _nodesSubscription?.cancel();
    _nodesSubscription = observeNodes().listen(
      (nodes) {
        if (!isClosed) {
          if (nodes.isEmpty) {
            add(const _NodesUpdatedEmpty());
          } else {
            add(_NodesUpdated(nodes));
          }
        }
      },
      onError: (error) {
        if (!isClosed) {
          add(_NodesLoadError(error.toString()));
        }
      },
    );
  }

  void _onNodesUpdated(_NodesUpdated event, Emitter<NodeListState> emit) {
    emit(NodeListLoaded(event.nodes));
  }

  void _onNodesUpdatedEmpty(
      _NodesUpdatedEmpty event, Emitter<NodeListState> emit) {
    emit(const NodeListEmpty());
  }

  void _onNodesLoadError(
      _NodesLoadError event, Emitter<NodeListState> emit) {
    emit(NodeListError(event.message));
  }

  @override
  Future<void> close() {
    _nodesSubscription?.cancel();
    return super.close();
  }
}

// ── Internal Events ──

class _NodesUpdated extends NodeListEvent {
  final List<Node> nodes;

  const _NodesUpdated(this.nodes);

  @override
  List<Object> get props => [nodes];
}

class _NodesUpdatedEmpty extends NodeListEvent {
  const _NodesUpdatedEmpty();
}

class _NodesLoadError extends NodeListEvent {
  final String message;

  const _NodesLoadError(this.message);

  @override
  List<Object> get props => [message];
}
