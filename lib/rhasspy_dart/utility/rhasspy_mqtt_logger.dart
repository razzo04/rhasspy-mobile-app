enum Level { debug, info, warning, error }

class Logger {
  static bool loggingEnable = true;
  static const prefix = {
    Level.debug: "[D]",
    Level.info: "[I]",
    Level.warning: "[W]",
    Level.error: "[E]"
  };
  void log(String message, Level level) {
    if (loggingEnable) print("${prefix[level]} $message");
  }
}
