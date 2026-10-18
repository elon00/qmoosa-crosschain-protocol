// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @title QmoosaHTLC
 * @notice Cross-Chain Hashed Time-Locked Contract (HTLC) supporting atomic swaps
 *         with SHA-256 secret commitments, explicit dual-chain binding, reentrancy guards,
 *         strict chain identity enforcement, fee-on-transfer token rejection,
 *         and mutual exclusion between claims and refunds.
 */
contract QmoosaHTLC {
    enum SwapState {
        INVALID,
        FUNDED,
        CLAIMED,
        REFUNDED
    }

    struct Swap {
        address sender;
        address recipient;
        address token;
        uint256 amount;
        bytes32 hashlock;       // SHA-256 hash of the secret preimage
        uint256 timelock;       // UNIX timestamp after which swap can be refunded
        uint256 sourceChainId;  // Source chain ID
        uint256 destChainId;    // Destination chain ID
        uint256 nonce;          // Replay defense nonce
        SwapState state;
    }

    uint256 public constant MIN_TIMELOCK_BUFFER = 300; // 5 minutes minimum buffer
    uint256 private _reentrancyStatus;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    mapping(bytes32 => Swap) public swaps;
    uint256 public totalSwapsCount;
    uint256 public activeSwapsCount;

    event SwapCreated(
        bytes32 indexed swapId,
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock,
        uint256 sourceChainId,
        uint256 destChainId,
        uint256 nonce
    );

    event SwapClaimed(
        bytes32 indexed swapId,
        bytes secret,
        address indexed claimer
    );

    event SwapRefunded(
        bytes32 indexed swapId,
        address indexed refunder
    );

    error ReentrancyGuardReentrantCall();
    error InvalidZeroAddress();
    error IdenticalSenderRecipient();
    error ZeroAmount();
    error InsufficientTimelock();
    error SwapAlreadyExists();
    error SwapNotFoundOrNotFunded();
    error SwapNotExpired();
    error SwapExpired();
    error InvalidSecretPreimage();
    error TokenTransferFailed();
    error ChainIdMismatch();
    error FeeOnTransferNotSupported();

    modifier nonReentrant() {
        if (_reentrancyStatus == _ENTERED) revert ReentrancyGuardReentrantCall();
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    constructor() {
        _reentrancyStatus = _NOT_ENTERED;
    }

    function calculateSwapId(
        address sender,
        address recipient,
        address token,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock,
        uint256 sourceChainId,
        uint256 destChainId,
        uint256 nonce
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                sender,
                recipient,
                token,
                amount,
                hashlock,
                timelock,
                sourceChainId,
                destChainId,
                nonce
            )
        );
    }

    function createSwap(
        address recipient,
        address token,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock,
        uint256 sourceChainId,
        uint256 destChainId,
        uint256 nonce
    ) external nonReentrant returns (bytes32 swapId) {
        if (sourceChainId != block.chainid) revert ChainIdMismatch();
        if (recipient == address(0) || token == address(0)) revert InvalidZeroAddress();
        if (recipient == msg.sender) revert IdenticalSenderRecipient();
        if (amount == 0) revert ZeroAmount();
        if (timelock <= block.timestamp + MIN_TIMELOCK_BUFFER) revert InsufficientTimelock();

        swapId = calculateSwapId(
            msg.sender,
            recipient,
            token,
            amount,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        if (swaps[swapId].state != SwapState.INVALID) revert SwapAlreadyExists();

        swaps[swapId] = Swap({
            sender: msg.sender,
            recipient: recipient,
            token: token,
            amount: amount,
            hashlock: hashlock,
            timelock: timelock,
            sourceChainId: sourceChainId,
            destChainId: destChainId,
            nonce: nonce,
            state: SwapState.FUNDED
        });

        totalSwapsCount++;
        activeSwapsCount++;

        // Strict fee-on-transfer / rebasing check
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        if (balanceAfter - balanceBefore != amount) revert FeeOnTransferNotSupported();

        emit SwapCreated(
            swapId,
            msg.sender,
            recipient,
            token,
            amount,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );
    }

    function claimSwap(bytes32 swapId, bytes calldata secret) external nonReentrant {
        Swap storage swap = swaps[swapId];
        if (swap.state != SwapState.FUNDED) revert SwapNotFoundOrNotFunded();
        if (block.timestamp > swap.timelock) revert SwapExpired();

        // Verify SHA-256 hashlock
        if (sha256(secret) != swap.hashlock) revert InvalidSecretPreimage();

        // Transition state before transfer to enforce Checks-Effects-Interactions & mutual exclusion
        swap.state = SwapState.CLAIMED;
        activeSwapsCount--;

        _safeTransfer(swap.token, swap.recipient, swap.amount);

        emit SwapClaimed(swapId, secret, msg.sender);
    }

    function refundSwap(bytes32 swapId) external nonReentrant {
        Swap storage swap = swaps[swapId];
        if (swap.state != SwapState.FUNDED) revert SwapNotFoundOrNotFunded();
        if (block.timestamp <= swap.timelock) revert SwapNotExpired();

        // Transition state before transfer to enforce Checks-Effects-Interactions & mutual exclusion
        swap.state = SwapState.REFUNDED;
        activeSwapsCount--;

        _safeTransfer(swap.token, swap.sender, swap.amount);

        emit SwapRefunded(swapId, msg.sender);
    }

    function getSwap(bytes32 swapId) external view returns (Swap memory) {
        return swaps[swapId];
    }

    function verifyPreimage(bytes32 hashlock, bytes calldata secret) external pure returns (bool) {
        return sha256(secret) == hashlock;
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed();
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert TokenTransferFailed();
        }
    }
}
