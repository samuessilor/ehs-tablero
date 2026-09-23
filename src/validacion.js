/**
 * Las reglas de frontera de la captura, en un solo sitio.
 *
 * Por que existe este archivo si la base de datos ya valida.
 *
 * Porque valida dos veces a proposito, y las dos veces hacen falta:
 *
 *   La base de datos valida porque es la ultima linea y la unica que no se puede
 *   rodear. Da igual quien escriba —este formulario, un script, el propio DBA con
 *   una consola abierta—: ehs.sp_capturar_lote comprueba lo mismo. Si la validacion
 *   viviera solo aqui, cualquier otro camino de escritura la saltaria entera.
 *
 *   El servidor valida porque la persona necesita saber que esta mal ANTES de que
 *   se grabe la mitad del mes, y con el nombre del campo al lado. Un error que
 *   vuelve del motor llega tarde y llega en el idioma del motor.
 *
 * Lo que NO puede pasar es que las dos discrepen. Por eso las reglas estan aqui como
 * datos, no como codigo disperso, y analisis/verificar_validacion_pareja.py comprueba
 * que este archivo y app/sql/04-ingesta.sql rechazan y advierten exactamente lo mismo
 * ante la misma entrada. Es la misma compuerta que ya cuida las vistas contra el motor.
 */

/* Las nueve magnitudes son las de ehs\CLAUDE.md. El orden es el de captura, no el
   alfabetico: agrupa lo que se lee del mismo recibo o de la misma planilla. */
const MAGNITUDES = [
  { id: 'agua_m3', etiqueta: 'Agua', unidad: 'm³', grupo: 'Ambiental' },
  { id: 'energia_kwh', etiqueta: 'Energía', unidad: 'kWh', grupo: 'Ambiental' },
  { id: 'residuo_peligroso_kg', etiqueta: 'Residuo peligroso', unidad: 'kg', grupo: 'Ambiental' },
  {
    id: 'residuo_aprovechable_kg',
    etiqueta: 'Residuo aprovechable',
    unidad: 'kg',
    grupo: 'Ambiental',
  },
  { id: 'residuo_ordinario_kg', etiqueta: 'Residuo ordinario', unidad: 'kg', grupo: 'Ambiental' },
  {
    id: 'unidades_buenas',
    etiqueta: 'Unidades buenas producidas',
    unidad: 'lentes',
    grupo: 'Producción',
  },
  {
    id: 'accidentes_dafw',
    etiqueta: 'Accidentes con días perdidos',
    unidad: 'casos',
    grupo: 'Seguridad',
  },
  { id: 'horas_fijos', etiqueta: 'Horas-hombre personal fijo', unidad: 'h', grupo: 'Seguridad' },
  { id: 'horas_temp', etiqueta: 'Horas-hombre personal temporal', unidad: 'h', grupo: 'Seguridad' },
];

const SITIOS = [
  { id: 'celta', etiqueta: 'Laboratorio Celta' },
  { id: 'estrella', etiqueta: 'Laboratorio La Estrella' },
  { id: 'agencias', etiqueta: 'Consolidado Agencias' },
];

/* Rango historico con 50% de holgura, el mismo que carga ehs.dim_magnitud. Se declara
   aqui porque el servidor tiene que poder advertir sin ida y vuelta al motor; el motor
   conserva el suyo porque es quien manda. verificar_validacion_pareja.py comprueba que
   no se separen. */
const RANGO = {
  agua_m3: [110, 913.5],
  energia_kwh: [21827, 282792],
  residuo_peligroso_kg: [15, 21060],
  residuo_aprovechable_kg: [400, 28701],
  residuo_ordinario_kg: [133, 6744],
  unidades_buenas: [29258.5, 165361.5],
  accidentes_dafw: [0, 1.5],
  horas_fijos: [19423.5, 161880],
  horas_temp: [0, 14982],
};

const MAG_IDS = new Set(MAGNITUDES.map((m) => m.id));
const SITIO_IDS = new Set(SITIOS.map((s) => s.id));

/* Mismo piso que ehs.sp_corregir_lectura (migracion 0009): un motivo de una
   palabra no es un motivo. */
const MOTIVO_MINIMO_CORRECCION = 10;

/** Numero decimal con punto o coma. Devuelve null si no lo es. */
function aNumero(texto) {
  if (texto === null || texto === undefined) return null;
  const s = String(texto).trim().replace(',', '.');
  if (s === '') return null;
  if (!/^-?\d+(\.\d+)?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/**
 * Examina una fila. Devuelve { motivo, advertencia }, ambos null si esta bien.
 *
 * motivo      lo IMPOSIBLE: no entra nunca, se arregla en el origen (R.5.3.5).
 * advertencia lo IMPROBABLE: entra solo si quien captura lo confirma.
 *
 * La distincion no es cosmetica. Un residuo negativo no existe; un consumo del doble
 * del maximo historico puede ser un cero de mas al teclear o puede ser la fuga que el
 * indicador existe para detectar. Rechazar el segundo deja el mes sin capturar y sin
 * nada que corregir.
 */
function examinarFila(fila) {
  const { anio, mes, sitio, magnitud, valor } = fila;

  if (valor === null || valor === undefined || String(valor).trim() === '') {
    return {
      motivo: 'Celda vacía. Una celda vacía no es un cero (R.5.3.6): no se captura.',
      advertencia: null,
    };
  }
  if (!Number.isInteger(anio) || anio < 2023 || anio > 2100) {
    return { motivo: `Año fuera de rango: ${anio}.`, advertencia: null };
  }
  if (!Number.isInteger(mes) || mes < 1 || mes > 12) {
    return { motivo: `Mes fuera de rango: ${mes}.`, advertencia: null };
  }
  if (!SITIO_IDS.has(sitio)) {
    return { motivo: `Sitio desconocido: ${sitio}.`, advertencia: null };
  }
  if (!MAG_IDS.has(magnitud)) {
    return { motivo: `Magnitud desconocida: ${magnitud}.`, advertencia: null };
  }

  const n = aNumero(valor);
  if (n === null) {
    return { motivo: `El valor no es un número: ${valor}.`, advertencia: null };
  }
  if (n < 0) {
    return {
      motivo: 'Valor negativo. Ninguna de las nueve magnitudes puede serlo.',
      advertencia: null,
    };
  }

  const rango = RANGO[magnitud];
  if (rango) {
    const [min, max] = rango;
    if (n > max) {
      return {
        motivo: null,
        advertencia:
          `Supera el máximo histórico de ${magnitud} con holgura (${max}). ` +
          'Confirma que es correcto.',
      };
    }
    if (n > 0 && n < min) {
      return {
        motivo: null,
        advertencia:
          `Queda por debajo del mínimo histórico de ${magnitud} (${min}). ` +
          'Confirma que es correcto.',
      };
    }
  }

  return { motivo: null, advertencia: null };
}

/**
 * Examina el lote entero y lo reparte en tres montones.
 *
 * Devuelve { validas, rechazadas, advertidas }. El que llama decide que hacer con
 * las advertidas segun venga o no la confirmacion: esta funcion no lo decide por el.
 */
function examinarLote(filas) {
  const validas = [];
  const rechazadas = [];
  const advertidas = [];

  for (const fila of filas) {
    const { motivo, advertencia } = examinarFila(fila);
    if (motivo) {
      rechazadas.push({ ...fila, motivo });
    } else if (advertencia) {
      advertidas.push({ ...fila, advertencia, valor: aNumero(fila.valor) });
    } else {
      validas.push({ ...fila, valor: aNumero(fila.valor) });
    }
  }
  return { validas, rechazadas, advertidas };
}

/**
 * La correccion de UN valor ya capturado (pantalla "Consultar y corregir"), distinta
 * de examinarFila: aqui el motivo es parte de lo que se examina, y no hay una fila de
 * "celda vacia" posible porque el valor viene de un campo numerico, no de texto libre.
 */
function examinarCorreccion({ magnitud, valor, motivo }) {
  const motivoTexto = motivo == null ? '' : String(motivo).trim();
  if (motivoTexto.length < MOTIVO_MINIMO_CORRECCION) {
    return {
      motivoInvalido: `El motivo tiene que explicar algo, no solo llenar el campo (mínimo ${MOTIVO_MINIMO_CORRECCION} caracteres).`,
    };
  }

  const n = aNumero(valor);
  if (n === null) {
    return {
      motivoInvalido: null,
      error: `El valor no es un número: ${valor}.`,
      advertencia: null,
    };
  }
  if (n < 0) {
    return {
      motivoInvalido: null,
      error: 'Valor negativo. Ninguna de las nueve magnitudes puede serlo.',
      advertencia: null,
    };
  }

  const rango = RANGO[magnitud];
  let advertencia = null;
  if (rango) {
    const [min, max] = rango;
    if (n > max) {
      advertencia = `Supera el máximo histórico de ${magnitud} con holgura (${max}). Confirma que es correcto.`;
    } else if (n > 0 && n < min) {
      advertencia = `Queda por debajo del mínimo histórico de ${magnitud} (${min}). Confirma que es correcto.`;
    }
  }

  return { motivoInvalido: null, error: null, advertencia, valor: n };
}

module.exports = {
  MAGNITUDES,
  SITIOS,
  RANGO,
  MOTIVO_MINIMO_CORRECCION,
  aNumero,
  examinarFila,
  examinarLote,
  examinarCorreccion,
};
