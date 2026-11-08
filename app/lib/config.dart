/// URL du serveur injectée à la compilation (`--dart-define=SERVER_URL=...`).
const String kDefaultServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'https://chess-trio-warriors.geoffroyd.workers.dev',
);

const String kAppName = 'Chess Trio Warriors';
const String kNotificationChannelId = 'turns';
