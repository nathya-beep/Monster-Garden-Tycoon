# Diseño: Trading entre jugadores

## Contexto

El MVP funciona de punta a punta (parcelas, semillas, cosecha, economía, inventario). Según `CLAUDE.md`, trading es la siguiente fase después del MVP. `InventoryService` ya es genérico por `itemId` (no conoce de semillas ni criaturas específicamente), así que el trading se construye sin tocarlo — funciona automáticamente con cualquier ítem presente o futuro.

## Alcance

- Intercambio de ítems de inventario (`itemId` -> cantidad) entre dos jugadores. Sin coins en el trade (solo ítems).
- Inicio por proximidad: acercarse a otro jugador y solicitar trade.
- Confirmación con doble lock y re-confirmación si cambia la oferta.
- Cancelación automática por distancia o desconexión.
- Validación 100% server-side (nunca confiar en el estado que reporta el cliente).

Fuera de alcance: coins en el trade, historial de trades, límites de trades por día, trading entre más de 2 jugadores, sistema de reputación/reportes.

## Diseño

### 1. Estado del trade (servidor)

`TradeService.lua` (nuevo, mismo patrón que `PlotService`/`EconomyService`) mantiene una tabla en memoria de trades activos, keyed por un `tradeId` generado, con esta forma:

```lua
export type TradeState = {
	TradeId: string,
	PlayerA: Player,
	PlayerB: Player,
	OfferA: { [string]: number }, -- itemId -> cantidad ofrecida
	OfferB: { [string]: number },
	LockedA: boolean,
	LockedB: boolean,
	CreatedAt: number, -- os.time()
}
```

Un jugador solo puede estar en un trade activo a la vez (`userId -> tradeId` como índice secundario para lookup rápido y para bloquear solicitudes duplicadas).

**Invariante clave:** cualquier cambio a `OfferA`/`OfferB` (agregar o quitar un ítem) resetea `LockedA = false` y `LockedB = false`. El trade se ejecuta únicamente en el instante en que una operación de lock deja `LockedA and LockedB` ambos en `true`.

### 2. Flujo de solicitud e inicio

- Cliente detecta jugadores cercanos (≤10 studs) via `Players:GetPlayers()` + distancia entre `HumanoidRootPart`, chequeado cada segundo (no necesita `ProximityPrompt` real, simplifica: solo mostrar/ocultar un botón "Solicitar Trade" apuntando al jugador más cercano dentro del rango).
- Cliente llama `RequestTrade(targetUserId)`. Servidor valida: el target existe, ninguno de los dos está ya en un trade, y la distancia real (server-side, no confía en la del cliente) es ≤10 studs. Si es válido, crea una notificación pendiente para el target (no crea el `TradeState` todavía).
- Target responde `RespondTradeRequest(fromUserId, accepted: boolean)`. Si acepta y ambos siguen sin trade activo y en rango, el servidor crea el `TradeState` y notifica a ambos clientes para abrir la UI.

### 3. Actualizar oferta

- `UpdateTradeOffer(tradeId, itemId, delta: number)` — `delta` positivo agrega esa cantidad de `itemId` de tu inventario a tu oferta, negativo la quita. Servidor valida:
  - El jugador es parte de ese `tradeId`.
  - Tras aplicar `delta`, la cantidad ofrecida de ese ítem no supera lo que el jugador tiene en inventario (`InventoryService.GetCount`), ni baja de 0.
  - Resetea ambos `Locked` a `false` (invariante de la sección 1).
  - Responde con el `TradeState` actualizado a ambos clientes (vía `RemoteEvent`, no `RemoteFunction`, porque hay que notificar al otro jugador también).

### 4. Confirmar / ejecutar

- `ConfirmTrade(tradeId)` marca `Locked<Self> = true`. Si el otro ya estaba `true`, el servidor **revalida todo desde cero** (ambos siguen teniendo en inventario lo que ofrecen — pudo cambiar entre el lock y el instante de ejecución) y si pasa, ejecuta: por cada ítem en `OfferA`, `InventoryService.RemoveItem(PlayerA, itemId, qty)` + `InventoryService.AddItem(PlayerB, itemId, qty)`, y simétricamente para `OfferB`. Si la revalidación falla para cualquier ítem, cancela el trade completo (no ejecuta parcialmente) y notifica el motivo a ambos.
- Tras ejecutar (éxito o fallo), se destruye el `TradeState` y se limpia el índice `userId -> tradeId`.

### 5. Cancelación

- `CancelTrade(tradeId)` — cualquiera de los dos puede cancelar en cualquier momento antes de la ejecución.
- Loop periódico del servidor (cada 2s, similar al `AUTO_COLLECT_INTERVAL_SECONDS` de `GrowthService`) recorre los trades activos: si la distancia entre `PlayerA` y `PlayerB` supera 15 studs, cancela.
- `Players.PlayerRemoving` cancela cualquier trade activo del jugador que se desconecta.
- Cancelar nunca transfiere ítems — es un no-op sobre el inventario, solo limpia el `TradeState`.

### 6. UI cliente

Archivo nuevo dedicado (no se mezcla con `Client.client.lua`, que ya maneja coins/tienda/parcelas): módulo separado para la UI de trading, con:
- Indicador/botón cuando hay un jugador cercano ("Solicitar Trade a `<Nombre>`").
- Notificación de solicitud entrante (Aceptar/Rechazar).
- Panel de trade activo: dos columnas (tu oferta / oferta del otro, ambas de solo lectura del lado ajeno), lista scrolleable de tu inventario para agregar cantidades, botones "Listo" y "Cancelar".
- El panel se cierra automáticamente si el servidor notifica cancelación (por distancia, desconexión, o rechazo de validación).

### 7. Remotes nuevos

Se agregan a `Remotes.lua` (mismo patrón `getOrCreateRemoteFunction`/equivalente para eventos): `RequestTrade`, `RespondTradeRequest`, `UpdateTradeOffer`, `ConfirmTrade`, `CancelTrade`, y un evento de servidor→cliente `TradeStateChanged` para notificar actualizaciones de estado a ambos jugadores en tiempo real (agregar/quitar ítems, lock, ejecución, cancelación).

## Testing

Validación manual en Studio con "Play - 2 Players" (Rojo/Studio soportan multi-cliente en Play Solo):
- Dos jugadores se acercan, uno solicita trade, el otro acepta.
- Agregar/quitar ítems de la oferta, confirmar que el lock del otro se resetea al cambiar.
- Ambos confirman → los inventarios se intercambian correctamente.
- Cancelar manualmente en cualquier punto → ningún ítem se mueve.
- Alejarse más de 15 studs durante un trade activo → se cancela automáticamente.
- Desconectar a un jugador durante un trade activo → el otro ve la cancelación.

No se agregan tests automatizados — mismo criterio que el resto del proyecto (sin infraestructura de testing Luau todavía).
