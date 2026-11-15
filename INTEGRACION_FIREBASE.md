# Conexión con Firebase

**Funciona en los dos sentidos.**

- La app manda una emergencia → la simulación la obedece.
- La historia de la simulación cambia de estado (por ejemplo, empieza la tormenta solar) → se lo avisa a la app.

La simulación pregunta cada 1 segundo el valor de esta ruta en Firebase Realtime Database:

```
https://thedox-spacehealth-default-rtdb.firebaseio.com/simulation_controls/active_scenario
```

| Valor que pone la app | Qué hace la simulación |
|---|---|
| `"normal"` (o vacío) | Sigue su historia sola, con sus propias emergencias en cada etapa |
| `"warning"` | Fuerza ADVERTENCIA en cualquier etapa |
| `"solarFlare"` | Fuerza CRÍTICO por tormenta solar |
| `"hypoxia"` | Fuerza CRÍTICO por falta de oxígeno |

Cuando la app fuerza una emergencia, cambia el estado de la cámara de cabina (color y texto), la reacción del astronauta y el texto de "qué siente la tripulación".
Apenas la app vuelve a `"normal"`, la simulación sigue con su historia en menos de un segundo.

Cuando la app pone `"normal"`, la simulación vuelve a su historia y escribe su propio estado en la misma ruta, así que la app pasa a mostrar lo que está pasando en la simulación.
Mientras la app está forzando una emergencia, la simulación no escribe nada en `active_scenario`: no le pisa la orden a la app.

Además, cada 2 segundos la simulación escribe en `simulation_controls/sim_state` la etapa (`stage`, `stage_name`), la fuerza G (`g`), la velocidad (`speed_kmh`) y la distancia (`distance_km`), por si la app quiere mostrarlos.

Los nombres tienen que ser **exactamente** esos (mayúsculas incluidas). Cualquier otro valor se toma como `"normal"`.

## Para cambiar el estado desde la app

Web (Firebase v9 o superior):

```js
import { getDatabase, ref, set } from "firebase/database";
set(ref(getDatabase(), "simulation_controls/active_scenario"), "hypoxia");
```

Android (Kotlin):

```kotlin
Firebase.database.getReference("simulation_controls/active_scenario").setValue("hypoxia")
```

## En el código

Todo está en `scripts/main.gd`, en la sección **FIREBASE** (`_start_firebase`, `_poll_firebase`, `_on_firebase`, `_push_scenario`, `_push_state`).
`last_synced` guarda lo último que la simulación escribió, para no confundir su propio valor con una orden de la app.
Las respuestas que llegan hasta 1,5 s después de que la simulación escribió se ignoran, porque pueden traer un valor viejo.
La URL está en la constante `FIREBASE_URL` y los textos de cada emergencia en `REMOTE_FEEL`.
Si no hay internet o Firebase no responde, la simulación sigue sola sin trabarse.

Las reglas de `simulation_controls` tienen que permitir leer y escribir (`".read": true, ".write": true`), porque la simulación es una página pública sin usuario.

## Volver a publicar la versión web

El link (`https://thonyferriel05.github.io/spacesapps/`) muestra lo que está en la carpeta `docs/`. Después de cambiar el código:

1. En Godot: **Editor → Manage Export Templates → Download and Install** (solo la primera vez).
2. **Project → Export → Web** (ya configurado para guardar en `docs/index.html`, con "Thread Support" apagado).
3. **Export Project**, desmarca "Export With Debug", guarda.
4. Commit y push. En un minuto el link ya tiene la versión nueva.
