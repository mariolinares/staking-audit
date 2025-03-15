## 1. Declaraciones de Licencia y Versión

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
```

- **Licencia:** Se especifica que el contrato utiliza la licencia MIT.
- **Versión:** El contrato utiliza Solidity versión 0.8.19, lo que permite aprovechar las características y protecciones propias de esta versión (por ejemplo, manejo de overflow/underflow nativo).

---

## 2. Importaciones

```solidity
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
```

- **SafeMath:** Biblioteca de OpenZeppelin para realizar operaciones aritméticas de forma segura (aunque en Solidity 0.8+ ya se controlan los overflows, sigue siendo útil en algunos casos para legibilidad).
- **IERC20:** Interfaz estándar para tokens ERC20, permitiendo interactuar con contratos de tokens.
- **Ownable:** Proporciona un mecanismo de control de acceso basado en un propietario, lo que facilita restricciones en funciones administrativas.
- **ReentrancyGuard:** Previene ataques de reentrancia, asegurando que ciertas funciones no puedan ser llamadas recursivamente.
- **Address:** Biblioteca con funciones utilitarias relacionadas con la dirección, como verificar si una dirección es un contrato.

---

## 3. Declaración del Contrato y Uso de Bibliotecas

```solidity
contract RottolabsStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using Address for address;
```

- **Herencia:** El contrato hereda de `Ownable` para manejo de propiedad y `ReentrancyGuard` para protección contra reentrancia.
- **Using:** Se emplean las funciones de SafeMath para tipos `uint256` y `uint128`, y se extienden las direcciones con funciones de la biblioteca Address.

---

## 4. Variables Globales y Estados

### Variables de Control y Contadores

```solidity
    uint128 public stakerCount;
    uint128 private planCount;
```

- **stakerCount:** Contador público del número de stakers activos.
- **planCount:** Contador privado de planes creados.

### Direcciones y Estados Administrativos

```solidity
    address private rottoAdminAddress = 0x37eF5480A6F43795fC5F1fCA5Dc78252a0c3507a;
    bool public contractActive;
```

- **rottoAdminAddress:** Dirección del administrador de Rotto, usada para funciones administrativas restringidas.
- **contractActive:** Flag que indica si el contrato está activo o inactivo.

### Constantes y Límites

```solidity
    uint256 private constant MIN_PLAN_PERCENT = 0;
    uint256 private constant MAX_PLAN_PERCENT = 100;
    uint256 public maxStakers = 150;
    uint256 private services = 14000000000000000;
```

- **MIN_PLAN_PERCENT y MAX_PLAN_PERCENT:** Límites para el porcentaje de recompensa de los planes.
- **maxStakers:** Número máximo de stakers permitidos en el contrato.
- **services:** Tarifa de servicio (en wei) que se debe enviar en ciertas transacciones.

### Gestión de Clientes

```solidity
    address[] private customerList;
    mapping(address => uint256) public customerActivePlans;
```

- **customerList:** Lista privada de direcciones de clientes (usuarios) que han interactuado con el staking.
- **customerActivePlans:** Mapea la dirección del cliente con el número de planes activos que tiene.

### Flags Adicionales para Control de Lógica

```solidity
    bool private rottoApprove;
    bool private activePlanForIncrementPercentage = true;
    bool public incrementPercentageUnblockPlans = true;
    bool private generateInitialPercentages = true;
```

- **rottoApprove:** Flag que indica si se tiene la aprobación de Rotto para realizar operaciones.
- **activePlanForIncrementPercentage:** Controla si se debe calcular el incremento en porcentaje de forma dinámica.
- **incrementPercentageUnblockPlans:** Otro flag relacionado con la lógica de incremento de porcentaje.
- **generateInitialPercentages:** Indica si se deben generar las distribuciones de porcentaje iniciales al desplegar el contrato.

### Límites de Planes y Suministro de Monedas

```solidity
    uint256 public totalPlans = 6;
    uint256 public maximunCoin = 400000000 * 10**9; // 400 millones
```

- **totalPlans:** Número total de planes inicialmente creados.
- **maximunCoin:** Máximo número de monedas que se pueden usar en staking.

### Incrementos en Porcentaje

```solidity
    uint256[] public rewardsPercentIncrement = [0, 1, 1, 2];
    uint256 private numberIncrements = 4;
```

- **rewardsPercentIncrement:** Array que define los incrementos en porcentaje que se aplicarán a un plan en función de repeticiones o condiciones definidas.
- **numberIncrements:** Número de incrementos definidos.

### Dirección de la Cartera del Tesoro

```solidity
    address public treasuryWallet;
```

- **treasuryWallet:** Dirección donde se envían las tarifas de servicio.

---

## 5. Estructuras de Datos

### Estructura Staker

```solidity
    struct Staker {
        uint256 id;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 percentage;
        uint256 rewards;
        uint256 selectedPlan;
        bool earlyWithdrawal;
    }
```

- **id:** Identificador único del stake del usuario.
- **amount:** Monto de tokens apostados.
- **startTime y endTime:** Tiempos de inicio y fin del período de staking.
- **percentage:** Porcentaje de recompensa aplicado al stake.
- **rewards:** Monto de recompensa calculado.
- **selectedPlan:** ID del plan seleccionado.
- **earlyWithdrawal:** Bandera que indica si se permite el retiro anticipado.

### Estructura Plan

```solidity
    struct Plan {
        uint128 id;
        uint128 percentage;
        uint256 position;
        uint256 duration;
        uint256 minAmount;
        uint256 maxAmount;
        bool earlyWithdrawal;
    }
```

- **id:** Identificador único del plan.
- **percentage:** Porcentaje base de recompensa del plan.
- **position:** Posición o categoría del plan, que puede estar relacionado con el orden o tipo de plan.
- **duration:** Duración del período de staking definido para el plan.
- **minAmount y maxAmount:** Monto mínimo y máximo que se puede apostar en el plan.
- **earlyWithdrawal:** Indica si se permite el retiro anticipado sin penalización o con condiciones especiales.

---

## 6. Mapeos y Estructuras de Datos para el Seguimiento

Se utilizan múltiples mappings para gestionar la información de staking y planes:

```solidity
    mapping(address => uint256) public staker_replays;
    mapping(address => Staker[]) private stakers;
    mapping(address => Plan[]) private plans;
    mapping(address => uint256[]) private userStakingComplete;
    mapping(address => mapping(uint256 => uint256)) public userPlansComplete;
    mapping(uint256 => mapping(uint256 => uint256)) public plansPercent;
    mapping(address => uint256) public stakingBalance;
    mapping(address => bool) public isStaking;
    mapping(address => uint256) public totalStakingBalance;
    mapping(address => uint256) public totalRewards;
    mapping(address => bool) public blacklist;
```

- **staker_replays:** Lleva la cuenta de las repeticiones o la cantidad de stakes realizados por un usuario.
- **stakers:** Almacena arrays de estructuras _Staker_ asociados a cada dirección.
- **plans:** Lista de planes asociados al contrato (usando la dirección del contrato como key).
- **userStakingComplete:** Historial de planes completados por cada usuario.
- **userPlansComplete:** Mapea, por cada usuario y plan, cuántas veces ha completado dicho plan.
- **plansPercent:** Define los porcentajes ajustados para cada plan en función de incrementos.
- **stakingBalance:** Monto apostado actual por cada usuario.
- **isStaking:** Bandera para indicar si el usuario tiene stakes activos.
- **totalStakingBalance:** Balance total de tokens apostados en el contrato.
- **totalRewards:** Recompensas totales asignadas (se registra para el owner).
- **blacklist:** Lista de usuarios bloqueados que no pueden participar en staking.

---

## 7. Eventos

```solidity
    event Staked(address indexed from, uint256 amount);
    event Claimed(address indexed from, uint256 amount);
    event SendMarketing(uint256 bnbSend);
    event ChangeServices(uint256 services);
```

- **Staked:** Se emite cuando un usuario realiza un stake.
- **Claimed:** Se emite cuando un usuario retira (deshace el stake) y reclama sus tokens junto con las recompensas.
- **SendMarketing:** Evento que indica el envío de tarifas a la cartera de tesorería.
- **ChangeServices:** Se emite cuando se modifica la tarifa de servicio.

---

## 8. Contrato del Token Externo

```solidity
    IERC20 private externalContract;
```

- **externalContract:** Variable que guarda la referencia al contrato ERC20 que se utilizará para las transacciones de staking (transferencias, comprobación de saldo, etc.).

---

## 9. Constructor

El constructor inicializa el contrato:

```solidity
    constructor(IERC20 _exteralContractAddress) {
        require(address(_exteralContractAddress) != address(0));
        externalContract = _exteralContractAddress;
```

- **Validación:** Se requiere que la dirección del contrato ERC20 no sea cero.
- **Inicialización:** Se asigna el contrato externo.

### Creación de Planes Iniciales

Se definen seis planes (dos grupos: sin y con posibilidad de retiro anticipado):

```solidity
        Plan memory zero = Plan({ ... });
        Plan memory one = Plan({ ... });
        Plan memory two = Plan({ ... });
        Plan memory three = Plan({ ... });
        Plan memory four = Plan({ ... });
        Plan memory five = Plan({ ... });
```

- Se establecen diferentes configuraciones para cada plan (porcentaje, duración, montos mínimo y máximo, y bandera de retiro anticipado).

Posteriormente, se agregan a la lista de planes:

```solidity
        plans[address(this)].push(zero);
        plans[address(this)].push(one);
        plans[address(this)].push(two);
        plans[address(this)].push(three);
        plans[address(this)].push(four);
        plans[address(this)].push(five);
```

### Inicialización de Variables de Estado

```solidity
        treasuryWallet = 0xb3cf72697b796A86FD0D52F73e1D8C7Ef3f4875D;
        rottoApprove = true;
        contractActive = true;
        stakerCount = 0;
        planCount = 6;
```

- Se asigna la cartera del tesoro y se activan las banderas de aprobación y actividad del contrato.
- Se inicializan los contadores de stakers y planes.

### Generación de Porcentajes Iniciales

```solidity
        if (generateInitialPercentages) {
            generateInitialPlansPercent();
        }
```

- Si la bandera está activa, se generan los porcentajes iniciales de los planes usando la función `generateInitialPlansPercent`.

---

## 10. Modificadores

Se definen varios modificadores para restringir el acceso o condiciones de ejecución:

- **notBlacklisted:** Requiere que el remitente no esté en la lista negra.
- **onlyWhenContractActive:** Solo permite ejecutar funciones cuando el contrato está activo.
- **onlyWhenContractInactive:** Permite ejecutar funciones cuando el contrato está inactivo.
- **onlyWhenRottoApprove:** Requiere que la bandera de aprobación de Rotto esté activa.
- **onlyWhenIsRottoAdmin:** Restringe la función al administrador designado de Rotto.
- **onlyWhenNoStakers:** Garantiza que no haya stakers activos para ciertas operaciones (por ejemplo, detener el contrato).

---

## 11. Funciones de Control del Contrato

### Activación/Desactivación del Contrato

```solidity
    function stopContract() external onlyWhenContractActive onlyWhenNoStakers { ... }
    function startContract() external onlyWhenContractInactive { ... }
```

- **stopContract:** Permite detener el contrato cuando está activo y no hay stakers (utilizando el modificador `onlyWhenNoStakers` para prevenir detenciones en medio de operaciones).
- **startContract:** Reactiva el contrato.

### Generación de Porcentajes Iniciales para los Planes

```solidity
    function generateInitialPlansPercent() private { ... }
```

- Itera sobre cada plan y cada incremento definido, estableciendo en el mapping `plansPercent` el valor base ajustado.
- Si el plan permite retiro anticipado (`earlyWithdrawal`), no se aplican incrementos.

### Función Interna para Encontrar el Índice de un Stake

```solidity
    function findStakerIndex(uint256 _id) internal view returns (uint256) { ... }
```

- Recorre la lista de stakes del usuario para encontrar el índice del stake cuyo `id` coincida con el parámetro.
- Si no se encuentra, se revierte con un mensaje.

---

## 12. Función de Staking

```solidity
    function stake(uint256 _amount, uint256 _selectedPlan)
        external
        payable
        nonReentrant
        notBlacklisted
        onlyWhenContractActive
        onlyWhenRottoApprove
    { ... }
```

Esta función permite a un usuario realizar un stake:

- **Validaciones previas:**

  - Se verifica que el nuevo balance total de staking no supere el límite de `maximunCoin`.
  - Se comprueba que el remitente no sea una dirección nula ni un contrato (solo cuentas EOA).
  - Se valida que el plan seleccionado existe y que el monto se encuentre dentro de los límites definidos en el plan.
  - Se impone el límite de stakers y se verifica el saldo y la allowance del token ERC20.
  - Se exige el pago de la tarifa de servicios (`services`), que se envía a la cartera del tesoro mediante `sendServices`.

- **Transferencia y registro:**
  - Se realiza la transferencia del token ERC20 desde el usuario al contrato.
  - Se calcula el porcentaje (posiblemente incrementado) para el plan mediante `calculatePercentage`.
  - Se crea un nuevo registro de tipo `Staker` y se almacena en el mapping `stakers` del usuario.
  - Se actualizan balances, contadores, y se emite el evento `Staked`.

---

## 13. Funciones para Consultar Planes y Stakes

- **getSelectedPlan:** Recorre el array de planes para encontrar aquel cuyo `id` coincida con el parámetro; si no se encuentra, revierte.
- **getSelectedProduct:** Similar a la anterior, pero para stakes del usuario.

---

## 14. Función para Deshacer el Stake (Unstaking)

```solidity
    function unstakeTokens(uint256 _id)
        external
        payable
        nonReentrant
        onlyWhenContractActive
        onlyWhenRottoApprove
    { ... }
```

- **Validaciones:**

  - Verifica que el usuario esté actualmente haciendo staking y que no se trate de un contrato.
  - Se obtiene el índice del stake mediante `findStakerIndex`.

- **Cálculo del monto a transferir:**

  - Se determina el monto original y las recompensas acumuladas.
  - Si el plan permite retiro anticipado y aún no finalizó el período, solo se devuelve el monto sin recompensa; de lo contrario, se devuelve el monto total (monto + recompensa).
  - Se valida que el contrato tenga saldo suficiente en tokens ERC20.

- **Transferencia y actualización:**
  - Se exige el pago de la tarifa de servicios.
  - Se transfiere el total al usuario y se actualizan los balances, tanto del usuario como del total en el contrato.
  - Se elimina el stake de la lista del usuario mediante `removeStakeByIndex` y se actualizan contadores y registros de clientes.
  - Se emite el evento `Claimed`.

### Función para Eliminar un Stake

```solidity
    function removeStakeByIndex(address _staker, uint256 index) internal { ... }
```

- **Funcionalidad:**
  - Si el usuario solo tiene un stake, se elimina y se marca que ya no está haciendo staking.
  - Si tiene más de uno, se elimina el stake reemplazándolo con el último elemento y haciendo pop para evitar huecos en el array.

---

## 15. Funciones Auxiliares

- **hasAllowance:** Comprueba que el usuario ha aprobado suficiente cantidad de tokens para ser transferidos por el contrato.
- **getStaker, getPlans, getPlansComplete:** Funciones de consulta para obtener información sobre stakes, planes y el historial completo de planes completados por un usuario.
- **\_generatePlanCompleteInfo:** Actualiza el historial de planes completados para un usuario (usa un delete para reinicializar el array y luego lo reconstruye).

- **getLength, getPlanLength, getTotalBalance:** Funciones para obtener la cantidad de stakes de un usuario, la cantidad de planes y el balance total en staking.

- **calculatePercentage:** Calcula el porcentaje de recompensa aplicable para un plan, teniendo en cuenta las repeticiones del usuario y los incrementos configurados.

- **calculateRewards:** Función pura que, dada una cantidad y un porcentaje, calcula el monto de recompensa. Se asegura que el porcentaje esté dentro del rango permitido.

---

## 16. Funciones de Administración de Planes

### Crear un Nuevo Plan

```solidity
    function createPlan(
        uint256 _position,
        uint128 _percentage,
        uint256 _duration,
        uint256 _minAmount,
        uint256 _maxAmount,
        bool _earlyWithdrawal
    ) external onlyOwner onlyWhenRottoApprove { ... }
```

- **Validaciones:**
  - Se verifica que el porcentaje esté dentro de límites, el monto mínimo sea positivo y menor que el máximo, y que la duración esté en un rango aceptable.
- **Creación:**
  - Se asigna un nuevo ID basado en la longitud actual de planes.
  - Se agrega el nuevo plan al array de planes.
  - Se actualiza el mapping `plansPercent` para el plan (estableciendo incrementos si el plan no permite retiro anticipado).
  - Se incrementan los contadores de planes.

### Eliminar un Plan

```solidity
    function deletePlan(uint256 _plan) external onlyOwner onlyWhenRottoApprove { ... }
```

- **Funcionalidad:**
  - Recorre la lista de planes para encontrar el plan a eliminar.
  - Si se encuentra, lo reemplaza con el último elemento y se hace pop del array.
  - Se actualiza el contador `totalPlans`.

---

## 17. Funciones de Configuración y Gestión de Tarifas

- **editServices:** Permite al propietario cambiar la tarifa de servicio, siempre que se encuentre en un rango definido.
- **updaterContractAddress:** Permite actualizar la dirección del contrato ERC20 con el que se interactúa.
- **changeMaxStakers:** Permite modificar el número máximo de stakers.
- **editTreasuryWallet:** Actualiza la dirección de la cartera del tesoro.
- **editRottoApprove:** Permite al administrador de Rotto cambiar el flag de aprobación.

### Gestión de Blacklist

- **addToBlacklist y removeFromBlacklist:** Permiten al propietario agregar o quitar usuarios de la lista negra.

### Función para Enviar Tarifas (Servicios)

```solidity
    function sendServices(address payable recipient, uint256 amount) private { ... }
```

- **Verificación:**
  - Se asegura de que el destinatario no sea un contrato.
  - Se verifica que el remitente tenga suficiente balance en Ether para cubrir la tarifa.
  - Se envía la cantidad usando un método de bajo nivel `call` y se emite el evento `SendMarketing`.

---

## 18. Función de Retiro de Balance

```solidity
    function withdrawalBalance()
        external
        onlyOwner
        onlyWhenRottoApprove
        onlyWhenNoStakers
    { ... }
```

- Permite al propietario retirar el saldo de tokens ERC20 del contrato, pero solo cuando no hay stakers activos.

---

## 19. Funciones de Consulta Final

- **totalRewardsPending:** Devuelve las recompensas totales pendientes acumuladas para el propietario.
- **customersList:** Retorna la lista de clientes que han interactuado con el staking.
- **changeMaxAvailableCoins:** Permite al propietario cambiar el límite máximo de monedas disponibles para staking.

---

## Conclusión

El contrato **RottolabsStaking** implementa un sistema de staking basado en planes predefinidos que determinan la duración, el monto y las recompensas (con posibilidad de incrementos) para cada stake. Se incluyen múltiples validaciones y restricciones, tanto para la seguridad (uso de `ReentrancyGuard` y validaciones de direcciones) como para la administración (funciones restringidas al propietario y a un administrador específico).
