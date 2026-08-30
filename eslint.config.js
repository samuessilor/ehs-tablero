// ESLint plano (R.3.3). Reglas base + navegador para el cliente.
const globalsNode = {
  require: 'readonly',
  module: 'writable',
  process: 'readonly',
  __dirname: 'readonly',
  console: 'readonly',
  Buffer: 'readonly',
  URL: 'readonly',
  setTimeout: 'readonly',
  clearTimeout: 'readonly',
};
const globalsNavegador = {
  window: 'readonly',
  document: 'readonly',
  fetch: 'readonly',
  console: 'readonly',
  URLSearchParams: 'readonly',
  history: 'readonly',
  location: 'readonly',
  echarts: 'readonly',
  requestAnimationFrame: 'readonly',
  Fmt: 'readonly',
  Graficos: 'readonly',
  FranjaCorreccion: 'readonly',
  setTimeout: 'readonly',
  clearTimeout: 'readonly',
  ResizeObserver: 'readonly',
};
module.exports = [
  {
    files: ['src/**/*.js', 'api/**/*.js', 'servidor.js'],
    languageOptions: { ecmaVersion: 2023, sourceType: 'commonjs', globals: globalsNode },
    rules: {
      'no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-undef': 'error',
      eqeqeq: ['error', 'smart'],
    },
  },
  {
    files: ['public/js/**/*.js'],
    languageOptions: { ecmaVersion: 2023, sourceType: 'script', globals: globalsNavegador },
    rules: {
      'no-unused-vars': [
        'error',
        { varsIgnorePattern: '^(Tablero|Graficos|FranjaCorreccion|Fmt)$' },
      ],
      'no-undef': 'error',
      eqeqeq: ['error', 'smart'],
    },
  },
];
