## 1. Encabezado y Declaraciones Iniciales

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
```

- **Licencia y versión:**  
  Se utiliza la licencia MIT y la versión 0.8.18 de Solidity, lo que garantiza que se aprovechen las protecciones nativas de esta versión (por ejemplo, chequeo de overflow).

---

## 2. Importaciones

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Import de Chainlink VRF v2
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
```

- **ReentrancyGuard, Ownable, Pausable:**  
  Se incorporan para proteger contra reentrancia, controlar el acceso (propietario) y pausar el contrato en caso de emergencia.
- **IERC20 y SafeERC20:**  
  Permiten interactuar de forma segura con tokens ERC20, usando la librería SafeERC20 para transferencias seguras.
- **Chainlink VRF:**  
  Se importan las interfaces y el contrato base de VRFConsumerBaseV2 para solicitar y recibir números aleatorios verificables.

---

## 3. Declaración del Contrato y Herencia

```solidity
contract BSCJackpot is VRFConsumerBaseV2, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;
```

- **Herencia múltiple:**  
  El contrato hereda de VRFConsumerBaseV2 (para integrar Chainlink VRF), ReentrancyGuard, Ownable y Pausable, lo que añade seguridad, control de acceso y la capacidad de pausar el funcionamiento.
- **using SafeERC20:**  
  Permite utilizar funciones seguras para interactuar con tokens ERC20.

---

## 4. Variables de Chainlink VRF

```solidity
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint16 private constant NUM_WORDS = 1;
```

- **i_vrfCoordinator:**  
  Dirección del coordinador VRF, que se utiliza para solicitar números aleatorios.
- **i_subscriptionId:**  
  ID de la suscripción a Chainlink VRF, necesario para autorizar las solicitudes.
- **i_gasLane:**  
  También conocido como keyHash o gas lane, determina el límite de gas para la llamada de retorno de Chainlink.
- **i_callbackGasLimit:**  
  Límite de gas que se usará en la función `fulfillRandomWords`.
- **REQUEST_CONFIRMATIONS y NUM_WORDS:**  
  Constantes que definen el número de confirmaciones requeridas y la cantidad de números aleatorios solicitados (en este caso, 1).

Además, se utiliza un mapping para relacionar el `requestId` de la solicitud de aleatoriedad con el ID interno de la lotería:

```solidity
    mapping(uint256 => uint256) private requestIdToLotteryId;
```

---

## 5. Variables y Estructuras de la Lotería

### Tarifas y Comisiones

```solidity
    uint256 public managerFeePercent = 15;
    uint256 public ownerFeePercent = 15;
    uint256 public constant MAX_FEE_PERCENT = 30;
    uint256 public participationFeeInBNB = 0.001 ether;
    uint256 public withdrawFeeInBNB = 0.001 ether;
```

- **managerFeePercent y ownerFeePercent:**  
  Porcentajes de comisión que se destinan al creador de la lotería (manager) y al propietario del contrato.
- **MAX_FEE_PERCENT:**  
  Límite máximo para las tarifas.
- **Tarifas fijas en BNB:**  
  Se definen las tarifas de participación y de retiro en BNB, obligatorias en cada transacción.

### Estado de la Lotería: Enum y Estructura

```solidity
    enum LotteryStatus {
        ONGOING,
        COMPLETED,
        CANCELLED
    }

    struct Lottery {
        string uuid;
        string name;
        address lotteryManager;
        address[] participants;
        uint256 totalJackpot;
        uint256 ticketPrice;
        address tokenAddress;
        uint256 closingTime;
        uint256 maxParticipants;
        uint256 minParticipants;
        address winnerAddress;
        LotteryStatus status;
    }
```

- **LotteryStatus:**  
  Enum que representa el estado de una lotería (en curso, completada o cancelada).
- **Lottery:**  
  La estructura contiene:
  - **uuid y name:** Identificadores y nombre de la lotería.
  - **lotteryManager:** Dirección del creador o administrador de la lotería.
  - **participants:** Lista de participantes.
  - **totalJackpot:** Monto total acumulado en premios.
  - **ticketPrice:** Precio del boleto.
  - **tokenAddress:** Dirección del token utilizado (si es cero, se entiende que la lotería usa BNB).
  - **closingTime:** Momento en que finaliza la lotería.
  - **maxParticipants y minParticipants:** Límites de participación.
  - **winnerAddress:** Dirección del ganador.
  - **status:** Estado actual de la lotería.

Además se maneja un array público de loterías y un mapping para relacionar un UUID (cadena única) con su índice en el array:

```solidity
    Lottery[] public lotteries;
    mapping(string => uint256) private uuidToIndex;
```

### Mecanismo de Reembolso (Pull Refunds)

```solidity
    mapping(string => mapping(address => uint256)) public refunds;
```

- Permite registrar, por cada lotería (identificada por UUID) y cada participante, el monto a reembolsar en caso de cancelación.

### Generador de UUID

```solidity
    uint256 private nonce = 0;
```

- Se utiliza un contador para generar UUID únicos, junto con otros parámetros.

---

## 6. Eventos

El contrato emite varios eventos para notificar acciones importantes:

- **LotteryCreated:** Cuando se crea una nueva lotería.
- **LotteryEntered:** Cuando un usuario entra en la lotería.
- **RandomnessRequested:** Al solicitar aleatoriedad a Chainlink.
- **WinnerPicked:** Al seleccionar el ganador.
- **LotteryCancelled:** Cuando se cancela una lotería.
- **LotteryFinalized:** Al finalizar y ajustar el jackpot.
- **FundsWithdrawn:** Cuando el ganador retira los fondos.
- **ContractPaused/Unpaused:** Eventos de pausa o reanudación.
- **ManagerFeePercentChanged/OwnerFeePercentChanged:** Para cambios en las tarifas.

---

## 7. Modificadores

Se definen modificadores para controlar el acceso y condiciones en funciones:

- **onlyManager:** Restringe funciones a que solo sean ejecutadas por el administrador de la lotería o el owner.
- **onlyUserWinner:** Permite que solo el ganador de una lotería ejecute la función.
- **lotteryExists:** Verifica que la lotería indicada exista (basada en su índice).

---

## 8. Constructor

```solidity
    constructor(
        address vrfCoordinatorV2,
        uint64 subscriptionId,
        bytes32 gasLane,
        uint32 callbackGasLimit
    )
        VRFConsumerBaseV2(vrfCoordinatorV2)
        ReentrancyGuard()
        Ownable()
        Pausable()
    {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
    }
```

- **Inicialización:**  
  Se configuran las variables inmutables de Chainlink VRF a partir de los parámetros del constructor. Además, se inicializan los contratos base heredados.

---

## 9. Función fulfillRandomWords (Chainlink VRF Callback)

```solidity
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 lotteryId = requestIdToLotteryId[requestId];
        Lottery storage lottery = lotteries[lotteryId];

        // Solo si aún está ONGOING (en caso de un callback tardío)
        if (lottery.status != LotteryStatus.ONGOING) {
            return;
        }

        require(
            lottery.participants.length >= lottery.minParticipants,
            "Not enough players"
        );
        require(lottery.totalJackpot > 0, "Jackpot must be greater than zero");

        // Elegimos ganador con randomWords[0]
        uint256 index = randomWords[0] % lottery.participants.length;
        address winner = lottery.participants[index];
        lottery.winnerAddress = winner;

        // Calcular comisiones
        uint256 totalJackpot = lottery.totalJackpot;
        uint256 managerFee = (totalJackpot * managerFeePercent) / 100;
        uint256 ownerFee = (totalJackpot * ownerFeePercent) / 100;
        uint256 remainingPrize = totalJackpot - managerFee - ownerFee;

        // Actualizamos la lotería
        lottery.totalJackpot = remainingPrize;
        lottery.status = LotteryStatus.COMPLETED;

        // Transferimos fees según el tipo de token (BNB o ERC20)
        if (lottery.tokenAddress == address(0)) {
            // BNB
            require(
                address(this).balance >= (managerFee + ownerFee),
                "Insufficient BNB for fees"
            );
            (bool successM, ) = lottery.lotteryManager.call{value: managerFee}("");
            require(successM, "Transfer to manager failed");
            (bool successO, ) = owner().call{value: ownerFee}("");
            require(successO, "Transfer to owner failed");
        } else {
            // Tokens ERC20
            IERC20 token = IERC20(lottery.tokenAddress);
            token.safeTransfer(lottery.lotteryManager, managerFee);
            token.safeTransfer(owner(), ownerFee);
        }

        emit LotteryFinalized(lotteryId, remainingPrize);
        emit WinnerPicked(lotteryId, winner, remainingPrize);
    }
```

- **Flujo de la función:**
  - Se obtiene el ID de la lotería a partir del `requestId` almacenado previamente.
  - Solo se procede si la lotería sigue en estado **ONGOING**.
  - Se comprueba que se haya alcanzado el mínimo de participantes y que el jackpot sea mayor que cero.
  - Se utiliza el número aleatorio para seleccionar un índice dentro del array de participantes.
  - Se calcula la comisión para el manager y el owner, descontándolas del jackpot y actualizando el estado de la lotería a **COMPLETED**.
  - Dependiendo de si la lotería usa BNB o tokens, se efectúan las transferencias de las tarifas de servicio mediante llamadas seguras.

---

## 10. Funciones de Gestión de Tarifas

```solidity
    function setManagerFeePercent(uint256 newManagerFeePercent) public onlyOwner { ... }
    function setOwnerFeePercent(uint256 newOwnerFeePercent) public onlyOwner { ... }
```

- Permiten al owner ajustar los porcentajes de comisión, siempre que no excedan el límite definido (30%).

---

## 11. Funciones de Lógica de Lotería

### Crear Lotería

```solidity
    function createLottery(
        string memory name,
        uint256 ticketPrice,
        uint256 duration,
        uint256 maxParticipants,
        uint256 minParticipants,
        address tokenAddress
    ) public whenNotPaused { ... }
```

- **Validaciones:**  
  Se asegura que ticketPrice, duration, maxParticipants y minParticipants sean mayores que cero y que el mínimo no exceda el máximo.
- **Generación de UUID:**  
  Se crea un identificador único para la lotería usando la función `generateUUID`.
- **Inicialización:**  
  Se inicializa la estructura **Lottery** con parámetros iniciales, se fija el closingTime (tiempo actual + duración) y se marca como **ONGOING**.
- **Almacenamiento:**  
  La lotería se agrega al array y se mapea su UUID a su índice, emitiendo el evento **LotteryCreated**.

### Participar en la Lotería

```solidity
    function enterLottery(string memory uuid) public payable nonReentrant whenNotPaused { ... }
```

- **Validaciones:**  
  Se verifica que la lotería exista, que esté en curso, que no haya alcanzado el máximo de participantes y que aún no haya finalizado.
- **Cobro de tarifas y ticketPrice:**  
  Dependiendo de si la lotería es en BNB o en tokens, se exige:
  - En BNB: que se envíe el monto exacto (ticketPrice + participationFeeInBNB) y se transfiere la tarifa al owner.
  - En tokens: se verifica la allowance y se transfiere el ticketPrice; además, se cobra la tarifa en BNB.
- **Registro:**  
  Se añade al participante y se emite el evento **LotteryEntered**.

### Solicitar el Ganador (pickWinner)

```solidity
    function pickWinner(string memory uuid) public onlyManager(uuidToIndex[uuid]) lotteryExists(uuidToIndex[uuid]) nonReentrant whenNotPaused { ... }
```

- **Condiciones para llamar:**  
  Solo el manager o el owner pueden ejecutar, y se requiere que la lotería ya haya finalizado (por tiempo o por alcanzar el máximo de participantes).
- **Solicitud a Chainlink:**  
  Se llama a `requestRandomWords` de Chainlink y se almacena la relación requestId ↔ lotteryId. Se emite el evento **RandomnessRequested**.

### Cancelar Lotería y Reembolsos

```solidity
    function cancelLottery(string memory uuid) public onlyManager(uuidToIndex[uuid]) lotteryExists(uuidToIndex[uuid]) nonReentrant whenNotPaused { ... }
```

- **Cancelación:**  
  Solo se puede cancelar si la lotería está en curso y ha superado el closingTime.
- **Registro de reembolsos:**  
  Se marca la lotería como **CANCELLED** y se registra el importe del ticketPrice para cada participante en el mapping `refunds`.
- **Evento:**  
  Se emite **LotteryCancelled** con el monto reembolsado.

Cada participante puede reclamar su reembolso posteriormente a través de:

```solidity
    function claimRefund(string memory uuid) public nonReentrant { ... }
```

- La función transfiere los fondos (BNB o tokens) y pone a cero el reembolso registrado.

### Retiro de Fondos por el Ganador

```solidity
    function withdrawFunds(string memory uuid) public payable onlyUserWinner(uuidToIndex[uuid]) lotteryExists(uuidToIndex[uuid]) nonReentrant whenNotPaused { ... }
```

- **Requisitos:**  
  Se permite solo al ganador, cuando la lotería ha sido completada y existe un jackpot positivo.
- **Cobro de tarifa de retiro:**  
  Se exige el envío de `withdrawFeeInBNB` en BNB.
- **Transferencia de premio:**  
  Se transfiere el jackpot al ganador en BNB o tokens, y se emite el evento **FundsWithdrawn**.

---

## 12. Funciones de Vista

El contrato proporciona varias funciones de consulta para obtener información:

- **currentContractBalance:** Devuelve el balance del contrato, ya sea en BNB o en el token especificado.
- **getParticipants, getTotalJackpot, getWinnerAddress:** Permiten consultar detalles específicos de una lotería a partir de su UUID.
- **getLotteriesByManager:** Filtra y devuelve las loterías creadas por un manager determinado.
- **getActiveLotteries:** Devuelve todas las loterías en estado **ONGOING**.

---

## 13. Funciones de Pausa y Emergencia

### Pausar y Reanudar el Contrato

```solidity
    function pause() public onlyOwner whenNotPaused { ... }
    function unpause() public onlyOwner whenPaused { ... }
```

- Permiten al owner pausar o reanudar el contrato, lo que es útil en situaciones de emergencia.

### Retiro de Fondos en Emergencia

```solidity
    function withdrawEmergency(address tokenAddress) public onlyOwner nonReentrant { ... }
```

- Permite al owner retirar cualquier fondo (BNB o tokens) del contrato en caso de emergencia, garantizando que se pueda salvar el capital en situaciones imprevistas.

---

## 14. Utilidades para Generación de UUID

```solidity
    function generateUUID(address manager) private returns (string memory) { ... }
    function toHexString(bytes32 data) private pure returns (string memory) { ... }
```

- **generateUUID:**  
  Usa el `nonce`, el timestamp actual, el hash del bloque anterior y la dirección del manager para generar un identificador único (UUID) a través de keccak256.
- **toHexString:**  
  Convierte un `bytes32` a una cadena hexadecimal, utilizada para representar el UUID.

---

## Conclusión

El contrato **BSCJackpot** implementa una lotería en la Binance Smart Chain (BSC) que integra Chainlink VRF para garantizar una selección aleatoria y verificable del ganador. Entre sus características destacan:

- **Seguridad:** Uso de ReentrancyGuard, Pausable y SafeERC20 para evitar ataques y gestionar emergencias.
- **Gestión de Comisiones:** Tarifas configurables para el manager y el owner, con límites máximos.
- **Flexibilidad en Moneda:** Soporte tanto para BNB como para tokens ERC20.
- **Interacción con Chainlink:** Solicitud de aleatoriedad para elegir el ganador de forma descentralizada y transparente.
- **Mecanismo de Reembolso:** En caso de cancelación, se implementa un sistema de “pull refunds” para que cada participante pueda reclamar su dinero.
