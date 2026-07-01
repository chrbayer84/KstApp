/**
 * Debug logging utility
 * Controlled by DEBUG environment variable (e.g., DEBUG=kst:* or DEBUG=kst:connection,kst:pushover)
 * In production (NODE_ENV=production), debug logging is disabled by default unless explicitly enabled.
 */

const isProduction = process.env.NODE_ENV === 'production';
const debugEnv = process.env.DEBUG || '';
const isDebugEnabled = !isProduction || debugEnv.includes('kst') || debugEnv === '*';

// Namespace filters
const enabledNamespaces = new Set<string>();
if (debugEnv) {
  debugEnv.split(',').forEach(ns => {
    enabledNamespaces.add(ns.trim());
  });
}

function isNamespaceEnabled(namespace: string): boolean {
  if (!isDebugEnabled) return false;
  if (debugEnv === '*' || debugEnv.includes('*')) return true;
  if (enabledNamespaces.has('kst:*')) return true;
  if (enabledNamespaces.has(namespace)) return true;

  // Check for wildcard match (e.g., kst:connection matches kst:connection:receive)
  for (const ns of enabledNamespaces) {
    if (ns.endsWith('*') && namespace.startsWith(ns.slice(0, -1))) {
      return true;
    }
  }
  return false;
}

interface LoggerOptions {
  namespace: string;
  color?: string;
  serialized?: boolean;
}

function getTimestamp(): string {
  return new Date().toISOString();
}

function formatMessage(namespace: string, level: string, message: string): string {
  return `[${getTimestamp()}] [${level.toUpperCase()}] [${namespace}] ${message}`;
}

class Logger {
  private namespace: string;
  private isEnabled: boolean;

  constructor(options: LoggerOptions) {
    this.namespace = options.namespace;
    this.isEnabled = isNamespaceEnabled(options.namespace);
  }

  /**
   * Log a debug message (only if debug is enabled)
   */
  debug(message: string, ...args: any[]): void {
    if (this.isEnabled) {
      console.log(formatMessage(this.namespace, 'DEBUG', message), ...args);
    }
  }

  /**
   * Log an info message (always shown)
   */
  info(message: string, ...args: any[]): void {
    console.log(formatMessage(this.namespace, 'INFO', message), ...args);
  }

  /**
   * Log a warning message (always shown)
   */
  warn(message: string, ...args: any[]): void {
    console.warn(formatMessage(this.namespace, 'WARN', message), ...args);
  }

  /**
   * Log an error message (always shown)
   */
  error(message: string, ...args: any[]): void {
    console.error(formatMessage(this.namespace, 'ERROR', message), ...args);
  }

  /**
   * Create a child logger with a sub-namespace
   */
  child(subNamespace: string): Logger {
    return new Logger({ namespace: `${this.namespace}:${subNamespace}` });
  }
}

/**
 * Create a new logger instance
 * @param namespace - The namespace for the logger (e.g., 'kst:connection')
 * @returns Logger instance
 */
export function createLogger(namespace: string): Logger {
  return new Logger({ namespace });
}

/**
 * Global logger for the application
 */
export const logger = createLogger('kst:app');

export default logger;
