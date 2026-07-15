import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:routspan/core/errors.dart';
import 'package:routspan/data/olax/olax_m100_client.dart';
import 'package:routspan/data/olax/zte_api_transport.dart';
import 'package:routspan/data/router_repository.dart';

enum ConnStatus { disconnected, connecting, connected, error }

class SessionState {
  const SessionState({
    this.status = ConnStatus.disconnected,
    this.repo,
    this.host,
    this.profileId,
    this.profileName,
    this.error,
  });

  final ConnStatus status;
  final RouterRepository? repo;
  final String? host;

  /// The saved profile this session belongs to (if connected via one).
  final String? profileId;
  final String? profileName;
  final String? error;

  bool get isConnected => status == ConnStatus.connected && repo != null;

  /// Best label for the app bar: the profile name, else the host.
  String get label => (profileName != null && profileName!.isNotEmpty)
      ? profileName!
      : (host ?? 'Router');
}

/// Owns the connection lifecycle and the live [RouterRepository] instance.
class SessionController extends Notifier<SessionState> {
  // Mirror of the active repo, kept so onDispose can close it. Riverpod 3
  // forbids reading `state` (a Ref op) inside lifecycle callbacks, so the
  // dispose hook closes over this field instead of `state.repo`.
  RouterRepository? _repo;

  @override
  SessionState build() {
    ref.onDispose(() => _repo?.dispose());
    return const SessionState();
  }

  Future<void> connect({
    required String host,
    required String password,
    bool reqprocDialect = false,
    String? profileId,
    String? name,
  }) async {
    _repo?.dispose();
    _repo = null;
    state = SessionState(
      status: ConnStatus.connecting,
      host: host,
      profileId: profileId,
      profileName: name,
    );

    final repo = OlaxM100Client(
      host: host,
      config: reqprocDialect ? ZteConfig.reqproc : ZteConfig.goform,
    );
    try {
      await repo.login(password);
      _repo = repo;
      state = SessionState(
        status: ConnStatus.connected,
        repo: repo,
        host: host,
        profileId: profileId,
        profileName: name,
      );
    } on RouterException catch (e) {
      repo.dispose();
      state = SessionState(
        status: ConnStatus.error,
        host: host,
        profileId: profileId,
        profileName: name,
        error: e.message,
      );
    } catch (e) {
      repo.dispose();
      state = SessionState(
        status: ConnStatus.error,
        host: host,
        profileId: profileId,
        profileName: name,
        error: '$e',
      );
    }
  }

  void disconnect() {
    _repo?.dispose();
    _repo = null;
    state = const SessionState();
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// The connected repository, or throws if not connected. UI providers read this.
RouterRepository _requireRepo(Ref ref) {
  final repo = ref.watch(sessionControllerProvider).repo;
  if (repo == null) {
    throw const AuthException('Not connected to a router.');
  }
  return repo;
}

/// Public handle to the live repository for performing actions (send SMS,
/// reboot, …). Throws [AuthException] if disconnected.
final repositoryProvider = Provider<RouterRepository>(_requireRepo);

final statusProvider = FutureProvider.autoDispose<DeviceStatus>((ref) async {
  return _requireRepo(ref).getStatus();
});

final dataUsageProvider = FutureProvider.autoDispose<DataUsage>((ref) async {
  return _requireRepo(ref).getDataUsage();
});
