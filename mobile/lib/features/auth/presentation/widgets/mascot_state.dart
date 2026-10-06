/// Interactive states for the RobotMascot during the login flow.
enum MascotState {
  /// Default state: gentle breathing, antenna sway, idle arm wave, blinking.
  idle,

  /// Triggered when the email or mobile number field is focused:
  /// smiling mouth, attentive eyes.
  emailFocus,

  /// Triggered when the password field is focused:
  /// privacy gesture — arms move up to cover eyes, eyes narrow.
  passwordFocus,

  /// Triggered on successful login:
  /// celebration bounce, happy eyes and smile.
  success,

  /// Triggered on login error:
  /// head shake animation, concerned expression, auto-reverts to idle.
  error,
}
