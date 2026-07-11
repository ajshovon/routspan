/// Errors surfaced by the router layer. Kept vendor-neutral so the UI never has
/// to know about ZTE/Dio specifics.
class RouterException implements Exception {
  const RouterException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'RouterException: $message';
}

/// The device could not be reached (wrong IP, not on the router's WiFi, or
/// traffic went out over cellular instead of the LAN).
class UnreachableException extends RouterException {
  const UnreachableException(super.message, {super.cause});
}

/// Login failed, or the session expired and re-login was not possible.
class AuthException extends RouterException {
  const AuthException(super.message, {super.cause});
}

/// The device replied but the operation failed (non-zero `result`).
class CommandFailedException extends RouterException {
  const CommandFailedException(super.message, {this.result, super.cause});

  final String? result;
}
